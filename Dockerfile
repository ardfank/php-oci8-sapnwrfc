FROM php:8.4-fpm
ENV DEBIAN_FRONTEND=noninteractive \
    RFC_TRACE=1 \
    RFC_TRACE_DIR=/var/log/entaah \
    COMPOSER_ALLOW_SUPERUSER=1 \
    PHP_INI_DIR=/usr/local/etc/php \
    ORACLE_HOME=/opt/oracle/instantclient \
    PATH=/opt/oracle/instantclient:${PATH}
RUN mkdir -p /var/log/entaah && chmod 777 -R /var/log/entaah
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg2 supervisor openssl ca-certificates curl git unzip libxml2-dev libaio-dev wget bash autoconf automake libtool \
    build-essential pkg-config libpng-dev libjpeg-dev libfreetype6-dev libzip-dev zlib1g-dev libpq-dev nano lsb-release

RUN wget http://deb.debian.org/debian/pool/main/liba/libaio/libaio1_0.3.113-4_amd64.deb \
    && dpkg -i libaio1_0.3.113-4_amd64.deb \
    && rm libaio1_0.3.113-4_amd64.deb    

RUN curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nginx.gpg] http://nginx.org/packages/debian $(lsb_release -cs) nginx" \
        > /etc/apt/sources.list.d/nginx.list
RUN apt-get update && apt-get install -y nginx

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" gd mysqli pdo_mysql pgsql pdo_pgsql zip \
    soap bcmath exif
COPY --from=ghcr.io/php/pie:bin /pie /usr/bin/pie    
RUN pie install phpredis/phpredis

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

RUN pie install oci8/oci8 --with-oci8=instantclient,/opt/oracle/instantclient/
RUN pie install pecl/pdo_oci --with-pdo_oci=instantclient,/opt/oracle/instantclient/ || \
    (find /root/.config/pie -path '*/vendor/pecl/pdo_oci/oci_statement.c' \
      -exec sed -i 's/EMPTY_SWITCH_DEFAULT_CASE();/default: ZEND_UNREACHABLE();/' {} \; \
      && cd "$(dirname "$(find /root/.config/pie -path '*/vendor/pecl/pdo_oci/Makefile' | head -1)")" \
      && make clean && make && make install) && docker-php-ext-enable pdo_oci
RUN cd /usr/src && git clone --depth=1 --single-branch https://github.com/gkralik/php7-sapnwrfc.git && cd php7-sapnwrfc \
    && find . -name '*.c' -exec sed -i \
        -e 's/XtOffsetOf(/offsetof(/g' \
        -e 's/ZVAL_IS_NULL(\&\([a-zA-Z_][a-zA-Z0-9_]*\))/Z_TYPE(\1) == IS_NULL/g' \
        {} + && sed -i '1i#include <stddef.h>' sapnwrfc.c \
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
