FROM php:8.4-fpm-bullseye
ENV DEBIAN_FRONTEND=noninteractive \
    COMPOSER_ALLOW_SUPERUSER=1 \
    PHP_INI_DIR=/usr/local/etc/php \
    ORACLE_HOME=/opt/oracle/instantclient \
    PATH=/opt/oracle/instantclient:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx supervisor openssl ca-certificates curl git unzip libaio1 libxml2-dev libaio-dev wget bash autoconf automake libtool \
    build-essential pkg-config libpng-dev libjpeg-dev libfreetype6-dev libzip-dev zlib1g-dev libpq-dev nano \
 && rm -rf /var/lib/apt/lists/*
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" gd mysqli pdo_mysql pgsql pdo_pgsql zip \
    soap bcmath
RUN pecl install redis && docker-php-ext-enable redis

RUN mkdir /opt/oracle
RUN wget https://download.oracle.com/otn_software/linux/instantclient/216000/instantclient-basic-linux.x64-21.6.0.0.0dbru.zip \
&& wget https://download.oracle.com/otn_software/linux/instantclient/216000/instantclient-sdk-linux.x64-21.6.0.0.0dbru.zip \
&& wget https://download.oracle.com/otn_software/linux/instantclient/216000/instantclient-sqlplus-linux.x64-21.6.0.0.0dbru.zip \
&& unzip instantclient-basic-linux.x64-21.6.0.0.0dbru.zip -d /opt/oracle \
&& unzip instantclient-sdk-linux.x64-21.6.0.0.0dbru.zip -d /opt/oracle \
&& unzip instantclient-sqlplus-linux.x64-21.6.0.0.0dbru.zip -d /opt/oracle \
&& rm -rf *.zip \
&& mv /opt/oracle/instantclient_21_6 /opt/oracle/instantclient
COPY nwrfcsdk.zip /opt/
RUN unzip /opt/nwrfcsdk.zip -d /usr/sap && rm -f /opt/nwrfcsdk.zip
RUN echo -e "/opt/oracle/instantclient\n/usr/sap/nwrfcsdk/lib" > /etc/ld.so.conf.d/oci.conf && ldconfig

RUN echo 'instantclient,/opt/oracle/instantclient/' | pecl install oci8
RUN docker-php-ext-enable oci8
RUN echo 'instantclient,/opt/oracle/instantclient,21.6' | pecl install pdo_oci
RUN docker-php-ext-enable pdo_oci
RUN cd /usr/src && git clone --depth=1 --branch=1.x --single-branch https://github.com/gkralik/php7-sapnwrfc.git && cd php7-sapnwrfc \
&& phpize && ./configure && make -j"$(nproc)" && make install
RUN echo "extension=sapnwrfc.so" > "${PHP_INI_DIR}/conf.d/docker-php-ext-sapnwrfc.ini"
RUN apt-get purge -y autoconf automake libtool && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php \
 && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm -f /tmp/composer-setup.php

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

RUN chown -R www-data:www-data /var/www/html
RUN php -m
EXPOSE 80
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
# CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]