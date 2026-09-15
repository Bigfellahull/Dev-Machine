#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"

log "Configuring access to OrbStack's host Docker CLI"
if ! command -v mac >/dev/null 2>&1; then
  warn "OrbStack's mac bridge is absent; leaving Docker unconfigured on this generic Ubuntu host."
  exit 0
fi

"$DEV_MACHINE_ROOT/orb/docker-api.sh"

if command -v docker >/dev/null 2>&1; then
  info "A docker command already exists; no link was changed."
else
  sudo mac link docker
  info "Linked the macOS Docker CLI with OrbStack's supported command bridge."
fi
