#!/bin/sh
set -eu
mkdir -p storage/app/public storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache
# PHP-FPM master must start as root to switch workers to www-data.
if [ "$1" = php-fpm ]; then exec "$@"; fi
exec gosu www-data "$@"
