#!/bin/sh
set -eu
cd /var/www/html
if [ -e storage/.installed ] || [ -e storage/.initializing ]; then
    echo 'Refusing initialization of an existing or partially initialized installation.' >&2
    exit 1
fi
# Never seed an existing database; seeds may affect existing tracker content.
# The quoted payload is PHP, whose variables must remain literal.
# shellcheck disable=SC2016
php -r '
$pdo = new PDO("mysql:host=".getenv("DB_HOST").";dbname=".getenv("DB_DATABASE"), getenv("DB_USERNAME"), getenv("DB_PASSWORD"));
if ($pdo->query("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()")->fetchColumn() != 0) { fwrite(STDERR, "Database must be empty.\n"); exit(1); }
'
touch storage/.initializing
php artisan migrate --seed --force
php artisan scout:sync-index-settings
php artisan scout:import 'App\Models\Torrent'
mv storage/.initializing storage/.installed
echo 'Database initialized. Never run db:seed on an existing installation.'
