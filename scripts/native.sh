#!/usr/bin/env bash

# shellcheck source=scripts/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
trap 'echo "Installation stopped at line $LINENO. Review the error above; do not rerun over a partial install." >&2' ERR
check_args "$@"
check_os
check_web_ports
PHP_VERSION=8.4
if [[ $ID == ubuntu && $VERSION_ID == 26.04 ]]; then PHP_VERSION=8.5; fi
[[ $EUID == 0 ]] || fail 'Run native installation with sudo.'
[[ -d /run/systemd/system ]] || fail 'Native mode requires a running systemd server.'
APP=/var/www/unit3d
ANNOUNCE_NGINX=
for path in "$APP" /var/lib/mysql /var/lib/meilisearch /etc/unit3d /opt/unit3d-announce /opt/unit3d-rust /etc/systemd/system/unit3d-announce.service /etc/nginx/sites-enabled/unit3d /etc/supervisor/conf.d/unit3d.conf; do
  [[ ! -e $path ]] || fail "Fresh server required: $path already exists."
done
check_existing_server_software
check_preinstalled_docker native
if [[ ${1:-} == --check ]]; then echo "Native preflight passed for $ID $VERSION_ID (no changes made)."; exit 0; fi
export DEBIAN_FRONTEND=noninteractive
umask 027
apt-get update
apt-get install -y ca-certificates curl gnupg openssl python3 git unzip
collect_settings
if [[ $INSTALL_ANNOUNCE == true ]] && command -v ss >/dev/null; then
  [[ -z $(ss -H -ltn 'sport = :6969') ]] || fail "Port 6969 is already in use."
fi
install -d -m 750 /etc/unit3d
# MySQL's signed official repository supplies MySQL 8.4 on all accepted hosts.
curl -fsSL "https://repo.mysql.com/apt/$ID/dists/$VERSION_CODENAME/Release" -o /etc/unit3d/mysql-release
curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 | gpg --dearmor -o /usr/share/keyrings/unit3d-mysql.gpg
chmod 644 /usr/share/keyrings/unit3d-mysql.gpg
printf 'deb [arch=amd64 signed-by=/usr/share/keyrings/unit3d-mysql.gpg] https://repo.mysql.com/apt/%s/ %s mysql-8.4-lts\n' "$ID" "$VERSION_CODENAME" > /etc/apt/sources.list.d/unit3d-mysql.list
if [[ $ID == ubuntu ]]; then
  apt-get install -y software-properties-common
  add-apt-repository -y universe
  if [[ $VERSION_ID == 24.04 ]]; then add-apt-repository -y ppa:ondrej/php; fi
fi
apt-get update
# Socket authentication for MySQL root; application has its own restricted user.
printf 'mysql-community-server mysql-community-server/root-pass password \nmysql-community-server mysql-community-server/re-root-pass password \n' | debconf-set-selections
apt-get install -y mysql-community-server nginx redis-server supervisor certbot python3-certbot-nginx nodejs composer \
  php${PHP_VERSION}-cli php${PHP_VERSION}-fpm php${PHP_VERSION}-common php${PHP_VERSION}-{bcmath,curl,gd,intl,mbstring,mysql,xml,zip,redis} \
  jpegoptim optipng pngquant gifsicle webp
if [[ $PHP_VERSION == 8.4 ]]; then apt-get install -y php8.4-opcache; fi
systemctl enable --now mysql redis-server php${PHP_VERSION}-fpm nginx supervisor
cat > /etc/mysql/conf.d/unit3d.cnf <<'EOF'
[mysqld]
bind-address=127.0.0.1
mysqlx-bind-address=127.0.0.1
EOF
systemctl restart mysql
mysql <<SQL
CREATE DATABASE unit3d CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'unit3d'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON unit3d.* TO 'unit3d'@'127.0.0.1';
SQL
printf '\nbind 127.0.0.1 ::1\nprotected-mode yes\nrequirepass %s\n' "$REDIS_PASSWORD" >> /etc/redis/redis.conf
chmod 640 /etc/redis/redis.conf
chown redis:redis /etc/redis/redis.conf
systemctl restart redis-server
useradd --system --home /var/lib/meilisearch --shell /usr/sbin/nologin meilisearch
install -d -o meilisearch -g meilisearch /var/lib/meilisearch
curl -fL "https://github.com/meilisearch/meilisearch/releases/download/v$MEILI_VERSION/meilisearch-linux-amd64" -o /usr/local/bin/meilisearch
chmod 755 /usr/local/bin/meilisearch
printf 'MEILI_ENV=production\nMEILI_HTTP_ADDR=127.0.0.1:7700\nMEILI_DB_PATH=/var/lib/meilisearch/data.ms\nMEILI_MASTER_KEY=%s\nMEILI_NO_ANALYTICS=true\n' "$MEILISEARCH_KEY" > /etc/unit3d/meilisearch.env
cat > /etc/systemd/system/unit3d-search.service <<'EOF'
[Unit]
Description=UNIT3D search
After=network.target
[Service]
User=meilisearch
Group=meilisearch
EnvironmentFile=/etc/unit3d/meilisearch.env
ExecStart=/usr/local/bin/meilisearch
Restart=on-failure
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now unit3d-search
for attempt in {1..60}; do
  if curl -fsS http://127.0.0.1:7700/health >/dev/null; then break; fi
  [[ $attempt -lt 60 ]] || fail "Meilisearch failed to start."
  sleep 1
done
curl -fL "https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION/bun-linux-x64-baseline.zip" -o /etc/unit3d/bun.zip
unzip -q /etc/unit3d/bun.zip -d /etc/unit3d/bun
install -m 755 /etc/unit3d/bun/bun-linux-x64-baseline/bun /usr/local/bin/bun
checkout_app "$APP"
python3 "$ROOT/scripts/configure.py" "$APP" native
chown -R www-data:www-data "$APP"
cd "$APP" || exit 1
runuser -u www-data -- php${PHP_VERSION} /usr/bin/composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader
runuser -u www-data -- bun install --frozen-lockfile
runuser -u www-data -- bun run build
runuser -u www-data -- env TRACKER_ENABLED=false php${PHP_VERSION} artisan migrate --seed --force
if [[ $INSTALL_ANNOUNCE == true ]]; then
  # shellcheck source=scripts/announce-native.sh
  source "$ROOT/scripts/announce-native.sh"
  install_native_announce
  ANNOUNCE_NGINX="include /etc/nginx/snippets/unit3d-announce.conf;"
fi
runuser -u www-data -- php${PHP_VERSION} artisan storage:link
runuser -u www-data -- php${PHP_VERSION} artisan scout:sync-index-settings
runuser -u www-data -- php${PHP_VERSION} artisan scout:import 'App\Models\Torrent'
runuser -u www-data -- php${PHP_VERSION} artisan config:cache
runuser -u www-data -- php${PHP_VERSION} artisan view:cache
# Keep code read-only to the web user; only storage and bootstrap cache writable.
chown -R root:www-data "$APP"
find "$APP" -type d -exec chmod 750 {} +
find "$APP" -type f -exec chmod u=rwX,g=rX,o= {} +
chown -R www-data:www-data "$APP/storage" "$APP/bootstrap/cache"
cat > /etc/nginx/sites-available/unit3d <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root $APP/public;
    index index.php;
    client_max_body_size 64m;
    $ANNOUNCE_NGINX
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location /socket.io/ {
        proxy_pass http://127.0.0.1:6001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 120s;
    }
    location = /index.php {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root/index.php;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    }
    location ~ \.php$ { return 404; }
    location ~ /\.(?!well-known).* { deny all; }
}
EOF
ln -s /etc/nginx/sites-available/unit3d /etc/nginx/sites-enabled/unit3d
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
certbot --nginx --non-interactive --agree-tos --redirect --email "$OWNER_EMAIL" -d "$DOMAIN"
cat > /etc/supervisor/conf.d/unit3d.conf <<EOF
[program:unit3d-queue]
command=/usr/bin/php${PHP_VERSION} $APP/artisan queue:work --sleep=3 --tries=3 --timeout=90 --max-time=3600
directory=$APP
user=www-data
numprocs=2
process_name=%(program_name)s_%(process_num)02d
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
stopwaitsecs=120
redirect_stderr=true
stdout_logfile=/var/log/unit3d-queue.log
[program:unit3d-echo]
command=/usr/bin/node $APP/node_modules/laravel-echo-server/bin/server.js start --dir=$APP
directory=$APP
user=www-data
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
redirect_stderr=true
stdout_logfile=/var/log/unit3d-echo.log
EOF
# Supervisor and node need executable binaries from the dependency tree.
find "$APP/node_modules" -type f -name '*.node' -exec chmod 750 {} +
cat > /etc/systemd/system/unit3d-schedule.service <<EOF
[Unit]
Description=UNIT3D scheduler
[Service]
Type=oneshot
User=www-data
WorkingDirectory=$APP
ExecStart=/usr/bin/php${PHP_VERSION} $APP/artisan schedule:run
EOF
cat > /etc/systemd/system/unit3d-schedule.timer <<'EOF'
[Unit]
Description=Run UNIT3D scheduler every minute
[Timer]
OnCalendar=*-*-* *:*:00
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now unit3d-schedule.timer
supervisorctl reread
supervisorctl update
printf 'URL: https://%s\nOwner: %s\nOwner password: %s\n' "$DOMAIN" "$OWNER_NAME" "$OWNER_PASSWORD" > /etc/unit3d/credentials.txt
chmod 600 /etc/unit3d/credentials.txt
printf 'Installed: https://%s\nCredentials: /etc/unit3d/credentials.txt\nConfigure SMTP and API keys in %s/.env, then rebuild config cache.\n' "$DOMAIN" "$APP"
