FROM debian:trixie-slim AS php74
RUN set -eux; \
    { \
        echo 'Package: php*'; \
        echo 'Pin: release *'; \
        echo 'Pin-Priority: -1'; \
    } > /etc/apt/preferences.d/no-debian-php
ENV PHPIZE_DEPS=" \
    autoconf \
    dpkg-dev \
    file \
    g++ \
    gcc \
    libc-dev \
    make \
    pkg-config \
    re2c \
"
ENV OPENSSL_PREFIX=/opt/openssl-1.1.1
ENV CURL_PREFIX=/opt/curl-openssl111
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PHPIZE_DEPS \
        ca-certificates \
        curl \
        perl \
        xz-utils \
        zlib1g-dev \
        libargon2-dev \
        libcrypt-dev \
        libonig-dev \
        libreadline-dev \
        libsodium-dev \
        libsqlite3-dev \
        libxml2-dev \
    ; \
    rm -rf /var/lib/apt/lists/*
ENV PHP_INI_DIR=/usr/local/etc/php
RUN set -eux; \
    mkdir -p "$PHP_INI_DIR/conf.d"; \
    mkdir -p /var/www/html; \
    chown www-data:www-data /var/www/html; \
    chmod 1777 /var/www/html
RUN set -eux; \
    cd /usr/src; \
    curl -fsSLO \
        https://www.openssl.org/source/old/1.1.1/openssl-1.1.1w.tar.gz; \
    echo "cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8  openssl-1.1.1w.tar.gz" \
        | sha256sum -c -; \
    tar -xzf openssl-1.1.1w.tar.gz; \
    cd openssl-1.1.1w; \
    ./config \
        --prefix="${OPENSSL_PREFIX}" \
        --openssldir="${OPENSSL_PREFIX}/ssl" \
        shared \
        zlib; \
    make -j"$(nproc)"; \
    make install_sw; \
    cd /; \
    rm -rf /usr/src/openssl-1.1.1w \
        /usr/src/openssl-1.1.1w.tar.gz
ENV CURL_VERSION=7.74.0
RUN set -eux; \
    cd /usr/src; \
    curl -fsSLO \
        "https://curl.se/download/curl-${CURL_VERSION}.tar.xz"; \
    tar -xJf "curl-${CURL_VERSION}.tar.xz"; \
    cd "curl-${CURL_VERSION}"; \
    export CPPFLAGS="-I${OPENSSL_PREFIX}/include"; \
    export LDFLAGS="-L${OPENSSL_PREFIX}/lib -Wl,-rpath,${OPENSSL_PREFIX}/lib"; \
    export PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/pkgconfig"; \
    ./configure \
        --prefix="${CURL_PREFIX}" \
        --with-openssl="${OPENSSL_PREFIX}" \
        --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
        --with-zlib \
        --without-libpsl \
        --without-brotli \
        --without-zstd \
        --without-libidn2 \
        --disable-static \
        --enable-shared; \
    make -j"$(nproc)"; \
    make install; \
    cd /; \
    rm -rf "/usr/src/curl-${CURL_VERSION}" \
        "/usr/src/curl-${CURL_VERSION}.tar.xz"
RUN set -eux; \
    printf '%s\n' "${OPENSSL_PREFIX}/lib" \
        > /etc/ld.so.conf.d/openssl-1.1.1.conf; \
    ldconfig; \
    "${OPENSSL_PREFIX}/bin/openssl" version; \
    LD_LIBRARY_PATH="${CURL_PREFIX}/lib:${OPENSSL_PREFIX}/lib" \
        "${CURL_PREFIX}/bin/curl" --version
ENV GPG_KEYS="42670A7FE4D0441C8E4632349E4FDC074A4EF02D 5A52880781F755608BF815FC910DEB46F53EA312"
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"
ENV PHP_VERSION=7.4.33
ENV PHP_URL="https://www.php.net/distributions/php-7.4.33.tar.xz" PHP_ASC_URL="https://www.php.net/distributions/php-7.4.33.tar.xz.asc"
ENV PHP_SHA256="924846abf93bc613815c55dd3f5809377813ac62a9ec4eb3778675b82a27b927"
RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends gnupg dirmngr; \
	rm -rf /var/lib/apt/lists/*; \
	\
	mkdir -p /usr/src; \
	cd /usr/src; \
	\
	curl -fsSL -o php.tar.xz "$PHP_URL"; \
	\
	if [ -n "$PHP_SHA256" ]; then \
		echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
	fi; \
	\
	if [ -n "$PHP_ASC_URL" ]; then \
		curl -fsSL -o php.tar.xz.asc "$PHP_ASC_URL"; \
		export GNUPGHOME="$(mktemp -d)"; \
		for key in $GPG_KEYS; do \
			gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key"; \
		done; \
		gpg --batch --verify php.tar.xz.asc php.tar.xz; \
		gpgconf --kill all; \
		rm -rf "$GNUPGHOME"; \
	fi; \
	\
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
COPY php74/docker-php-source /usr/local/bin/
RUN set -eux; \
    docker-php-source extract; \
    cd /usr/src/php; \
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    \
    export CFLAGS="${PHP_CFLAGS}"; \
    export CPPFLAGS="${PHP_CPPFLAGS} -I${OPENSSL_PREFIX}/include -I${CURL_PREFIX}/include"; \
    export LDFLAGS="${PHP_LDFLAGS} -L${OPENSSL_PREFIX}/lib -L${CURL_PREFIX}/lib -Wl,-rpath,${OPENSSL_PREFIX}/lib -Wl,-rpath,${CURL_PREFIX}/lib"; \
    export PKG_CONFIG_PATH="${CURL_PREFIX}/lib/pkgconfig:${OPENSSL_PREFIX}/lib/pkgconfig"; \
    \
    if [ ! -d /usr/include/curl ]; then \
        ln -sT "/usr/include/${debMultiarch}/curl" /usr/local/include/curl; \
    fi; \
    \
    ./configure \
        --build="${gnuArch}" \
        --with-config-file-path="${PHP_INI_DIR}" \
        --with-config-file-scan-dir="${PHP_INI_DIR}/conf.d" \
        --enable-option-checking=fatal \
        --with-mhash \
        --with-pic \
        --enable-ftp \
        --enable-mbstring \
        --enable-mysqlnd \
        --with-password-argon2 \
        --with-sodium=shared \
        --with-pdo-sqlite=/usr \
        --with-sqlite3=/usr \
        --with-curl="${CURL_PREFIX}" \
        --with-iconv \
        --with-openssl="${OPENSSL_PREFIX}" \
        --with-readline \
        --with-zlib \
        --disable-phpdbg \
        --with-pear \
        --with-libdir="lib/${debMultiarch}" \
        --disable-cgi \
        --enable-fpm \
        --with-fpm-user=www-data \
        --with-fpm-group=www-data; \
    \
    make -j"$(nproc)"; \
    find -type f -name '*.a' -delete; \
    make install; \
    \
    find /usr/local \
        -type f \
        -perm /0111 \
        -exec sh -euxc 'strip --strip-all "$@" || :' -- '{}' +; \
    \
    make clean; \
    cp -v php.ini-* "${PHP_INI_DIR}/"; \
    cd /; \
    docker-php-source delete
COPY php74/docker-php-ext-* php74/docker-php-entrypoint /usr/local/bin/
RUN docker-php-ext-enable sodium
RUN echo 'openssl.cafile=/etc/ssl/certs/ca-certificates.crt' >  "${PHP_INI_DIR}/conf.d/ssl.ini"
RUN set -eux; \
    php --version; \
    php --ri openssl; \
    php --ri curl; \
    php -r 'echo "OpenSSL: ", OPENSSL_VERSION_TEXT, PHP_EOL;'; \
    php -r 'echo "cURL: ", curl_version()["version"], PHP_EOL;'
ENTRYPOINT ["docker-php-entrypoint"]
WORKDIR /var/www/html
RUN set -eux; \
    cd /usr/local/etc; \
    if [ -d php-fpm.d ]; then \
        sed 's!=NONE/!=!g' php-fpm.conf.default \
            | tee php-fpm.conf > /dev/null; \
        cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
    else \
        mkdir -p php-fpm.d; \
        cp php-fpm.conf.default php-fpm.d/www.conf; \
        { \
            echo '[global]'; \
            echo 'include=etc/php-fpm.d/*.conf'; \
        } | tee php-fpm.conf; \
    fi; \
    { \
        echo '[global]'; \
        echo 'error_log = /proc/self/fd/2'; \
        echo 'log_limit = 8192'; \
        echo; \
        echo '[www]'; \
        echo 'access.log = /proc/self/fd/2'; \
        echo 'clear_env = no'; \
        echo 'catch_workers_output = yes'; \
        echo 'decorate_workers_output = no'; \
    } | tee php-fpm.d/docker.conf; \
    { \
        echo '[global]'; \
        echo 'daemonize = no'; \
        echo; \
        echo '[www]'; \
        echo 'listen = 9000'; \
    } | tee php-fpm.d/zz-docker.conf
STOPSIGNAL SIGQUIT
EXPOSE 9000
CMD ["php-fpm"]

FROM php74
ENV DEBIAN_FRONTEND=noninteractive \
    RFC_TRACE=1 \
    RFC_TRACE_DIR=/var/log/entaah \
    COMPOSER_ALLOW_SUPERUSER=1 \
    PHP_INI_DIR=/usr/local/etc/php \
    ORACLE_HOME=/opt/oracle/instantclient \
    PATH=/opt/oracle/instantclient:${PATH} \
    CFLAGS="-D_GNU_SOURCE -D_DEFAULT_SOURCE -std=gnu99"
RUN mkdir -p /var/log/entaah && chmod 777 -R /var/log/entaah
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg2 supervisor openssl ca-certificates curl git unzip libxml2-dev libaio-dev wget bash autoconf automake libtool \
    build-essential pkg-config libpng-dev libjpeg-dev libfreetype6-dev libzip-dev zlib1g-dev libpq-dev nano lsb-release

RUN apt-get update && apt-get install -y wget \
    && wget http://deb.debian.org/debian/pool/main/liba/libaio/libaio1_0.3.113-4_amd64.deb \
    && dpkg -i libaio1_0.3.113-4_amd64.deb \
    && rm libaio1_0.3.113-4_amd64.deb    

RUN curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nginx.gpg] http://nginx.org/packages/debian $(lsb_release -cs) nginx" \
        > /etc/apt/sources.list.d/nginx.list
RUN apt-get update && apt-get install -y nginx

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" gd mysqli pdo_mysql pgsql pdo_pgsql zip \
    soap bcmath exif
RUN pecl channel-update pecl.php.net 
RUN pecl install redis-5.3.7 && docker-php-ext-enable redis

RUN mkdir /opt/oracle
RUN wget https://download.oracle.com/otn_software/linux/instantclient/216000/instantclient-basic-linux.x64-21.6.0.0.0dbru.zip \
&& wget https://download.oracle.com/otn_software/linux/instantclient/216000/instantclient-sdk-linux.x64-21.6.0.0.0dbru.zip \
&& wget https://download.oracle.com/otn_software/linux/instantclient/216000/instantclient-sqlplus-linux.x64-21.6.0.0.0dbru.zip \
&& unzip instantclient-basic-linux.x64-21.6.0.0.0dbru.zip -d /opt/oracle \
&& unzip instantclient-sdk-linux.x64-21.6.0.0.0dbru.zip -d /opt/oracle \
&& unzip instantclient-sqlplus-linux.x64-21.6.0.0.0dbru.zip -d /opt/oracle \
&& rm -rf *.zip \
&& mv /opt/oracle/instantclient_21_6 /opt/oracle/instantclient
COPY nwrfc750P_15-70002752.zip /opt/nwrfcsdk.zip
RUN unzip /opt/nwrfcsdk.zip -d /usr/sap && rm -f /opt/nwrfcsdk.zip
RUN echo "/opt/oracle/instantclient\n/usr/sap/nwrfcsdk/lib" > /etc/ld.so.conf.d/oci.conf && ldconfig

RUN echo 'instantclient,/opt/oracle/instantclient/' | pecl install oci8-2.2.0
RUN docker-php-ext-enable oci8
RUN docker-php-ext-configure pdo_oci --with-pdo-oci=instantclient,/opt/oracle/instantclient,21.6
RUN set -eux; \
    cd /usr/src/php; \
    sed -i \
        -e 's/^static size_t oci_blob_read(/static ssize_t oci_blob_read(/' \
        -e 's/return (size_t)-1;/return -1;/' \
        ext/pdo_oci/oci_statement.c
RUN docker-php-ext-install pdo_oci
RUN docker-php-ext-enable pdo_oci
RUN cd /usr/src && git clone --depth=1 --branch=1.x --single-branch https://github.com/gkralik/php7-sapnwrfc.git && cd php7-sapnwrfc \
&& phpize && ./configure && make -j"$(nproc)" && make install

RUN echo "extension=sapnwrfc.so" > "${PHP_INI_DIR}/conf.d/docker-php-ext-sapnwrfc.ini"
RUN echo "log_errors = On\nerror_log = /var/log/entaah/php_error.log" > "${PHP_INI_DIR}/conf.d/docker-log.ini"

RUN apt-get purge -y autoconf automake libtool && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
RUN sed -i 's#access_log .*;#access_log /var/log/entaah/nginx-access.log;#' /etc/nginx/nginx.conf
RUN sed -i 's#error_log .*;#error_log /var/log/entaah/nginx-error.log;#' /etc/nginx/nginx.conf
RUN rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf || true
RUN set -eux; \
    mkdir -p /var/www/html; \
    printf '%s\n' \
'server {' \
'    listen 80;' \
'    server_name _;' \
'    root /var/www/html;' \
'    index index.php index.html;' \
'' \
'    location / {' \
'        try_files $uri $uri/ /index.php?$args;' \
'    }' \
'' \
'    location ~ \.php$ {' \
'        include fastcgi_params;' \
'        fastcgi_pass 127.0.0.1:9000;' \
'        fastcgi_index index.php;' \
'        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;' \
'    }' \
'' \
'    location ~ /\.ht {' \
'        deny all;' \
'    }' \
'}' \
    > /etc/nginx/conf.d/default.conf

RUN mkdir -p /etc/supervisor/conf.d
RUN printf '%s\n' \
'[supervisord]' \
'nodaemon=true' \
'' \
'[program:php-fpm]' \
'command=/usr/local/sbin/php-fpm -F' \
'autostart=true' \
'autorestart=true' \
'' \
'[program:nginx]' \
'command=/usr/sbin/nginx -g "daemon off;"' \
'autostart=true' \
'autorestart=true' \
> /etc/supervisor/conf.d/supervisord.conf
EXPOSE 80
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chown -R www-data:www-data /var/www/html
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]