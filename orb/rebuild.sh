#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=orb/lib.sh
. "$SCRIPT_DIR/lib.sh"

profile=${1:-}
[ -n "$profile" ] || orb_usage_error "Usage: rebuild.sh work|personal [--yes] [--dry-run] [--skip-ai]"
shift
load_profile "$profile"

yes=0
skip_ai=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) yes=1 ;;
    --dry-run) DEV_DRY_RUN=1 ;;
    --skip-ai) skip_ai=1 ;;
    *) orb_usage_error "Unknown rebuild option: $1" ;;
  esac
  shift
done
export DEV_DRY_RUN

require_orbctl
validate_create_inputs 1
confirm_delete "$DEV_MACHINE_NAME" "$yes"
destroy_args=("$profile" primary --yes)
create_args=("$profile")
if [ "$DEV_DRY_RUN" -eq 1 ]; then
  destroy_args+=(--dry-run)
  create_args+=(--dry-run)
fi
if [ "$skip_ai" -eq 1 ]; then
  create_args+=(--skip-ai)
fi

"$SCRIPT_DIR/destroy.sh" "${destroy_args[@]}"
"$SCRIPT_DIR/create.sh" "${create_args[@]}"
