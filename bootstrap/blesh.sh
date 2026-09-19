#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
require_target_ubuntu

log "Installing the latest ble.sh nightly build"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
curl -fsSL \
  https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz \
  -o "$temp_dir/ble-nightly.tar.xz"
tar -xJf "$temp_dir/ble-nightly.tar.xz" -C "$temp_dir"
bash "$temp_dir/ble-nightly/ble.sh" --install "$HOME/.local/share"
