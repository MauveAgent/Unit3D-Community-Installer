#!/usr/bin/env bash
# Compatibility entry point; the legacy PHP installer is no longer invoked.
set -Eeuo pipefail
exec bash "$(dirname -- "${BASH_SOURCE[0]}")/install.sh" native "$@"
