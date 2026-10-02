#!/usr/bin/env bash

# shellcheck source=scripts/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
trap 'echo "Docker installation stopped at line $LINENO. Keep /opt/unit3d for diagnosis; do not delete volumes." >&2' ERR
check_args "$@"
check_os
check_web_ports
[[ $EUID == 0 ]] || fail 'Run Docker bootstrap with sudo.'
DEPLOY=/opt/unit3d
[[ ! -e $DEPLOY ]] || fail 'Fresh deployment required: /opt/unit3d already exists.'
for path in /var/lib/mysql /var/lib/meilisearch /etc/unit3d /var/www/unit3d /opt/unit3d-announce /opt/unit3d-rust; do
  [[ ! -e $path ]] || fail "Fresh server required: $path already exists."
done
check_existing_server_software
check_preinstalled_docker docker
if [[ ${1:-} == --check ]]; then echo "Docker preflight passed for $ID $VERSION_ID (no changes made)."; exit 0; fi
umask 027
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg git openssl python3
collect_settings
if ! command -v docker >/dev/null; then
  curl -fsSL "https://download.docker.com/linux/$ID/dists/$VERSION_CODENAME/Release" -o /tmp/unit3d-docker-release
  install -d -m 755 /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/unit3d-docker.asc
  chmod 644 /etc/apt/keyrings/unit3d-docker.asc
  printf 'deb [arch=amd64 signed-by=/etc/apt/keyrings/unit3d-docker.asc] https://download.docker.com/linux/%s %s stable\n' "$ID" "$VERSION_CODENAME" > /etc/apt/sources.list.d/unit3d-docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi
docker compose version >/dev/null || fail 'Docker Compose v2 plugin is required.'
install -d -m 750 "$DEPLOY/docker"
cp "$ROOT/docker/"{Dockerfile,announce.Dockerfile,nginx.conf,entrypoint.sh,initialize.sh,php.ini} "$DEPLOY/docker/"
cp "$ROOT/docker/compose.yml" "$DEPLOY/compose.yml"
cp "$ROOT/docker/.dockerignore" "$DEPLOY/.dockerignore"
checkout_app "$DEPLOY/app"
if [[ $INSTALL_ANNOUNCE == true ]]; then
  checkout_announce "$DEPLOY/announce"
  python3 "$ROOT/scripts/announce-configure.py" "$DEPLOY/announce" docker
  chown 10001:10001 "$DEPLOY/announce/.env"
  chmod 400 "$DEPLOY/announce/.env"
fi
python3 "$ROOT/scripts/configure.py" "$DEPLOY/app" docker
chown root:33 "$DEPLOY/app/.env"
# Echo runs as uid 1000 inside its container. It needs read-only access to its configuration.
chown 1000:1000 "$DEPLOY/app/laravel-echo-server.json"
chmod 400 "$DEPLOY/app/laravel-echo-server.json"
printf 'DOMAIN=%s\nDB_PASSWORD=%s\nDB_ROOT_PASSWORD=%s\nREDIS_PASSWORD=%s\nMEILISEARCH_KEY=%s\n' "$DOMAIN" "$DB_PASSWORD" "$DB_ROOT_PASSWORD" "$REDIS_PASSWORD" "$MEILISEARCH_KEY" > "$DEPLOY/.env"
if [[ $INSTALL_ANNOUNCE == true ]]; then printf 'COMPOSE_PROFILES=announce\n' >> "$DEPLOY/.env"; fi
# Bind mounts contain secrets; the host directory is root-only.
chmod 600 "$DEPLOY/.env"
printf '{\n    email %s\n}\n%s {\n    reverse_proxy web:80\n}\n' "$OWNER_EMAIL" "$DOMAIN" > "$DEPLOY/docker/Caddyfile"
if [[ $INSTALL_ANNOUNCE == true ]]; then
  python3 "$ROOT/scripts/announce-proxy.py" "$DEPLOY/docker/Caddyfile"
fi
printf 'bind 0.0.0.0\nprotected-mode yes\nappendonly yes\nrequirepass %s\n' "$REDIS_PASSWORD" > "$DEPLOY/docker/redis.conf"
chmod 644 "$DEPLOY/docker/redis.conf"
cd "$DEPLOY" || exit 1
docker compose config --quiet
docker compose build
docker compose up -d --wait mysql redis meilisearch
docker compose run --rm init
if [[ $INSTALL_ANNOUNCE == true ]]; then docker compose up -d --wait announce; fi
docker compose up -d
printf 'URL: https://%s\nOwner: %s\nOwner password: %s\n' "$DOMAIN" "$OWNER_NAME" "$OWNER_PASSWORD" > credentials.txt
chmod 600 credentials.txt
printf 'Installed: https://%s\nCredentials: /opt/unit3d/credentials.txt\nManage with: cd /opt/unit3d && sudo docker compose ...\n' "$DOMAIN"
