#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/../bootstrap/lib.sh"
require_target_ubuntu

unit=dev-machine-docker-api.service
unit_path="$HOME/.config/systemd/user/$unit"
helper="$HOME/.local/bin/orbstack-docker-api"
policy=$(docker_api_bridge_policy) || die "Invalid Docker API bridge policy"
if [ "$policy" = enabled ]; then
  install_user_file "$DEV_MACHINE_ROOT/bin/orbstack-docker-api" "$helper" 0755
  install_user_file "$DEV_MACHINE_ROOT/config/systemd/$unit" "$unit_path"
  systemctl --user daemon-reload
  info "Docker API helper installed; commission it with docs/docker-api.md."
else
  if [ -e "$unit_path" ] || [ -L "$unit_path" ] \
    || systemctl --user is-active --quiet "$unit" 2>/dev/null \
    || systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
    systemctl --user disable --now "$unit"
    rm -f "$unit_path"
    systemctl --user daemon-reload
  fi
  rm -f "$helper"
  if [ -e "$HOME/.config/dev-machine/docker-api" ] || [ -L "$HOME/.config/dev-machine/docker-api" ]; then
    die "Disabled bridge credentials remain; revoke the matching Mac key and remove this VM's exact docker-api directory after review"
  fi
fi
