#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"

profile=${DEV_MACHINE_PROFILE:-}
skip_ai=0
verify_only=0

usage() {
  cat <<'USAGE'
Usage: bootstrap.sh --profile work|personal [--skip-ai] [--verify-only]

Provision the current non-root user on Ubuntu 26.04 ARM64. Authentication is
intentionally separate from provisioning.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || die "--profile requires work or personal"
      profile=$2
      shift 2
      ;;
    --skip-ai)
      skip_ai=1
      shift
      ;;
    --verify-only)
      verify_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown bootstrap option: $1"
      ;;
  esac
done

case "$profile" in
  work|personal) ;;
  *) die "Choose a profile with --profile work or --profile personal." ;;
esac

[ "$(id -u)" -ne 0 ] || die "Run bootstrap as the normal development user, not root."
require_target_ubuntu

# shellcheck disable=SC1090,SC1091
. "$DEV_MACHINE_ROOT/profiles/common.env"
# shellcheck disable=SC1090,SC1091
. "$DEV_MACHINE_ROOT/profiles/$profile.env"
export DEV_MACHINE_PROFILE DEV_CODE_DIR DEV_INSTALL_AI_TOOLS
export DEV_INSTALL_DOTNET_WASM_TOOLS DEV_INSTALL_WORK_TOOLS
export DEV_MACHINE_DB_ENGINES

if [ "$verify_only" -eq 1 ]; then
  verify_args=()
  if [ "$skip_ai" -eq 1 ]; then
    verify_args+=(--skip-ai)
  fi
  exec "$SCRIPT_DIR/verify.sh" "${verify_args[@]}"
fi

log "Provisioning the $profile development profile"
if ! sudo -n true 2>/dev/null; then
  sudo -v
fi

"$SCRIPT_DIR/base.sh"
"$SCRIPT_DIR/memory.sh"
"$SCRIPT_DIR/dotnet.sh"
"$SCRIPT_DIR/runtimes.sh"
"$SCRIPT_DIR/workstation-tools.sh"
if [ "$DEV_INSTALL_WORK_TOOLS" -eq 1 ]; then
  "$SCRIPT_DIR/work-tools.sh"
fi
"$SCRIPT_DIR/ocr.sh"

if [ "$skip_ai" -eq 0 ] && [ "$DEV_INSTALL_AI_TOOLS" -eq 1 ]; then
  "$SCRIPT_DIR/ai-tools.sh"
else
  warn "AI CLI installation was skipped."
fi

"$SCRIPT_DIR/shell.sh"
"$SCRIPT_DIR/docker-bridge.sh"

log "Provisioning complete"
verify_command="bootstrap/verify.sh"
if [ "$skip_ai" -eq 1 ]; then
  verify_command="$verify_command --skip-ai"
fi
info "From the dev-machine checkout, open a new shell and run: $verify_command"
info "Authentication remains a manual post-bootstrap step."
