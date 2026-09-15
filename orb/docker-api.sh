#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/../bootstrap/lib.sh"
require_target_ubuntu

unit=dev-machine-docker-api.service
unit_path="$HOME/.config/systemd/user/$unit"
helper="$HOME/.local/bin/orbstack-docker-api"
if [ "$DEV_MACHINE_PROFILE" = work ]; then
  install_user_file "$DEV_MACHINE_ROOT/bin/orbstack-docker-api" "$helper" 0755
  install_user_file "$DEV_MACHINE_ROOT/config/systemd/$unit" "$unit_path"
  systemctl --user daemon-reload
  info "Docker API helper installed; commission it with docs/docker-api.md."
else
  if [ -e "$unit_path" ]; then
    systemctl --user disable --now "$unit"
    rm -f "$unit_path"
    systemctl --user daemon-reload
  fi
  rm -f "$helper"
  if [ -d "$HOME/.config/dev-machine/docker-api" ]; then
    die "Work tunnel credentials remain on a personal VM; rebuild with separate runtime state"
  fi
fi
