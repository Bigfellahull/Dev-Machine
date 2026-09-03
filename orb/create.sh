#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=orb/lib.sh
. "$SCRIPT_DIR/lib.sh"

profile=${1:-}
[ -n "$profile" ] || orb_usage_error "Usage: create.sh work|personal [--dry-run] [--no-provision] [--skip-ai]"
shift
load_profile "$profile"

provision=1
skip_ai=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DEV_DRY_RUN=1 ;;
    --no-provision) provision=0 ;;
    --skip-ai) skip_ai=1 ;;
    *) orb_usage_error "Unknown create option: $1" ;;
  esac
  shift
done
export DEV_DRY_RUN
require_orbctl

validate_create_inputs "$provision"

if machine_exists "$DEV_MACHINE_NAME"; then
  orb_die "Machine already exists: $DEV_MACHINE_NAME"
fi

create_args=(
  create
  --arch "$DEV_ORB_ARCH"
  --memory "$DEV_MACHINE_MEMORY"
  --disk "$DEV_MACHINE_DISK"
  --user-data "$DEV_MACHINE_ROOT/orb/cloud-init.yaml"
)
if [ -n "$DEV_MACHINE_CPUS" ]; then
  create_args+=(--cpus "$DEV_MACHINE_CPUS")
fi
create_args+=("$DEV_ORB_DISTRO" "$DEV_MACHINE_NAME")

orb_log "Creating $DEV_MACHINE_NAME ($DEV_ORB_DISTRO, $DEV_ORB_ARCH)"
run_orbctl "${create_args[@]}"

if [ "$provision" -eq 1 ]; then
  provision_args=("$profile")
  if [ "$DEV_DRY_RUN" -eq 1 ]; then
    provision_args+=(--dry-run)
  fi
  if [ "$skip_ai" -eq 1 ]; then
    provision_args+=(--skip-ai)
  fi
  "$SCRIPT_DIR/provision.sh" "${provision_args[@]}"
fi
