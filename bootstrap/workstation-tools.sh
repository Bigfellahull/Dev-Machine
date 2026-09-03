#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
require_target_ubuntu

log "Installing common workstation libraries and database clients from Ubuntu"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  libpq-dev \
  postgresql-client
