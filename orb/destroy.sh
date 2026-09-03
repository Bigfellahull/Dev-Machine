#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=orb/lib.sh
. "$SCRIPT_DIR/lib.sh"

profile=${1:-}
kind=${2:-}
[ -n "$profile" ] && [ -n "$kind" ] \
  || orb_usage_error "Usage: destroy.sh work|personal primary|experiment [name] [--yes] [--dry-run]"
shift 2
load_profile "$profile"

case "$kind" in
  primary)
    target=$DEV_MACHINE_NAME
    ;;
  experiment)
    experiment_name=${1:-}
    [ -n "$experiment_name" ] || orb_usage_error "An exact experiment name is required."
    shift
    target=$(experiment_machine_name "$experiment_name")
    ;;
  *)
    orb_usage_error "Destroy kind must be primary or experiment."
    ;;
esac

yes=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) yes=1 ;;
    --dry-run) DEV_DRY_RUN=1 ;;
    *) orb_usage_error "Unknown destroy option: $1" ;;
  esac
  shift
done
export DEV_DRY_RUN
require_orbctl

if [ "$DEV_DRY_RUN" -eq 0 ] && ! machine_exists "$target"; then
  orb_die "Machine does not exist: $target"
fi

confirm_delete "$target" "$yes"
orb_log "Permanently deleting exact machine: $target"
run_orbctl delete --force "$target"

