#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/../bootstrap/lib.sh"
require_target_ubuntu

if [ "$DEV_MACHINE_PROFILE" = work ]; then
  install_user_file "$DEV_MACHINE_ROOT/bin/orbstack-windows-build" "$HOME/.local/bin/orbstack-windows-build" 0755
  install_user_file "$DEV_MACHINE_ROOT/config/rust-toolchain" "$HOME/.local/share/dev-machine/rust-toolchain"
  info "Windows build helper installed; run orbstack-windows-build provision after commissioning Parallels."
else
  rm -f "$HOME/.local/bin/orbstack-windows-build" "$HOME/.local/share/dev-machine/rust-toolchain"
fi
