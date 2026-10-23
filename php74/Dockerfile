FROM debian:trixie-slim
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
COPY docker-php-source /usr/local/bin/
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
COPY docker-php-ext-* docker-php-entrypoint /usr/local/bin/
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