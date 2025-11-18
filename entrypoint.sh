#!/usr/bin/env bash
set -e
# chown -R www-data:www-data /var/www/html
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
