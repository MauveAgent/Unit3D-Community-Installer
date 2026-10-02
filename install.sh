#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
case ${1:-native} in
  native) shift "$(( $# > 0 ? 1 : 0 ))"; exec bash "$ROOT/scripts/native.sh" "$@" ;;
  docker) shift; exec bash "$ROOT/scripts/docker.sh" "$@" ;;
  --help|-h) printf '%s\n' 'Usage: ./install.sh [native|docker] [--check]' 'See README.md for configuration and requirements.' 'Repository: https://github.com/MauveAgent/Unit3D-Community-Installer.git' ;;
  *) echo 'Unknown mode. Use native or docker.' >&2; exit 2 ;;
esac
