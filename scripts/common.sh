#!/usr/bin/env bash
# Shared constants are consumed by the sourcing installer scripts.
# shellcheck disable=SC2034
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UNIT3D_REF=${UNIT3D_REF:-v9.2.0}
UNIT3D_COMMIT=8b88f4c8182eb3d3912ffef425c3224dcfd596f4
BUN_VERSION=1.3.0
MEILI_VERSION=1.15.2
ANNOUNCE_REF=v0.3.1
ANNOUNCE_COMMIT=fcd189e9aebf07a12a1f8cc39500819c3870925b
RUST_VERSION=1.93.1
INSTALLER_REPOSITORY=https://github.com/MauveAgent/Unit3D-Community-Installer.git
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
check_os() {
  # /etc/os-release is supplied by the operating system, not user input.
  # shellcheck disable=SC1090
  source "${OS_RELEASE_FILE:-/etc/os-release}"
  case "$ID:$VERSION_ID" in
    debian:13|ubuntu:24.04|ubuntu:26.04) ;;
    *) fail 'Only Debian 13, Ubuntu 24.04 LTS and Ubuntu 26.04 LTS are accepted.' ;;
  esac
  [[ $(uname -m) == x86_64 ]] || fail 'This installer currently requires an amd64/x86_64 server.'
}
check_args() {
  [[ $# -le 1 && ${1:---check} == --check ]] || fail 'Only --check is accepted; configure using environment variables.'
}
check_web_ports() {
  if command -v ss >/dev/null; then
    [[ -z $(ss -H -ltn '( sport = :80 or sport = :443 )') ]] || fail "Ports 80/443 are already in use."
  fi
}
check_existing_server_software() {
  local service package
  # Docker and its own dependencies are the only allowed preinstalled stack.
  for service in nginx apache2 caddy mysql mariadb redis-server supervisor postgresql unit3d-search unit3d-announce; do
    if systemctl is-active --quiet "$service"; then fail "Fresh server required: $service is running."; fi
  done
  for package in nginx apache2 caddy mysql-server mysql-community-server mariadb-server redis-server supervisor postgresql nodejs composer 'php*-cli' 'php*-fpm'; do
    if dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null | grep -q 'install ok installed'; then
      fail "Fresh server required: $package is installed. Only Docker may be preinstalled."
    fi
  done
  for package in bun meilisearch unit3d-announce; do
    if command -v "$package" >/dev/null; then fail "Fresh server required: $package is installed. Only Docker may be preinstalled."; fi
  done
}
check_preinstalled_docker() {
  local containers
  if ! command -v docker >/dev/null; then return 0; fi
  cat >&2 <<'EOF'

WARNING: Docker is already installed on this server.
You may continue, provided no other server/application stack is installed,
no Docker containers exist, and the required ports are available.
Preinstalled Docker is used AS IS. No support or guarantees are provided.
If issues arise, you are on your own and assume all risks, liabilities,
responsibilities and outcomes from continuing.

EOF
  docker info >/dev/null 2>&1 || fail 'Preinstalled Docker daemon is unavailable. Start or repair it so existing containers can be checked.'
  containers=$(docker ps -aq) || fail 'Unable to inspect preinstalled Docker containers.'
  [[ -z $containers ]] || fail 'Fresh server required: Docker containers already exist.'

}
collect_settings() {
  if [[ -z ${DOMAIN:-} ]]; then read -r -p 'Tracker domain (DNS must point to this server): ' DOMAIN; fi
  [[ $DOMAIN =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]] || fail 'Enter a domain name without protocol, path or port.'
  if [[ -z ${OWNER_EMAIL:-} ]]; then read -r -p 'Owner email: ' OWNER_EMAIL; fi
  [[ $OWNER_EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,63}$ ]] || fail 'Invalid owner email.'
  OWNER_NAME=${OWNER_NAME:-Owner}
  [[ $OWNER_NAME =~ ^[a-zA-Z0-9_-]{3,30}$ ]] || fail 'Owner name must be 3–30 letters, digits, underscores or hyphens.'
  # Generated credentials avoid SQL/shell/dotenv interpolation vulnerabilities.
  OWNER_PASSWORD=$(openssl rand -hex 24)
  DB_PASSWORD=$(openssl rand -hex 24)
  DB_ROOT_PASSWORD=$(openssl rand -hex 24)
  REDIS_PASSWORD=$(openssl rand -hex 24)
  MEILISEARCH_KEY=$(openssl rand -hex 32)
  APP_KEY="base64:$(openssl rand -base64 32)"
  select_announce
  export DOMAIN OWNER_EMAIL OWNER_NAME OWNER_PASSWORD DB_PASSWORD DB_ROOT_PASSWORD REDIS_PASSWORD MEILISEARCH_KEY APP_KEY
}
checkout_app() {
  git clone --depth 1 --branch "$UNIT3D_REF" https://github.com/HDInnovations/UNIT3D.git "$1"
  if [[ $UNIT3D_REF == v9.2.0 ]]; then
    [[ $(git -C "$1" rev-parse HEAD) == "$UNIT3D_COMMIT" ]] || fail 'The upstream tag changed; review it before installing.'
  fi
}

select_announce() {
  local answer
  if [[ -z ${INSTALL_ANNOUNCE:-} ]]; then
    if [[ -t 0 ]]; then
      read -r -p 'Install optional Rust UNIT3D-Announce tracker? [y/N]: ' answer
      case "$answer" in y|Y|yes|YES) INSTALL_ANNOUNCE=true ;; *) INSTALL_ANNOUNCE=false ;; esac
    else
      INSTALL_ANNOUNCE=false
    fi
  fi
  case "$INSTALL_ANNOUNCE" in true|false) ;; *) fail 'INSTALL_ANNOUNCE must be true or false.' ;; esac
  if [[ $INSTALL_ANNOUNCE == true ]]; then
    [[ $UNIT3D_REF == v9.2.0 ]] || fail 'The optional tracker is reviewed only with UNIT3D v9.2.0.'
    TRACKER_KEY=$(openssl rand -hex 32)
    export TRACKER_KEY
  fi
  export INSTALL_ANNOUNCE
}
checkout_announce() {
  git clone --depth 1 --branch "$ANNOUNCE_REF" https://github.com/Roardom/UNIT3D-Announce.git "$1"
  [[ $(git -C "$1" rev-parse HEAD) == "$ANNOUNCE_COMMIT" ]] || fail 'The announce tag changed; review before installing.'
}
