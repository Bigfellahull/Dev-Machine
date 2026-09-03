#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=orb/lib.sh
. "$SCRIPT_DIR/lib.sh"

profile=${1:-}
experiment_name=${2:-}
[ -n "$profile" ] && [ -n "$experiment_name" ] \
  || orb_usage_error "Usage: clone.sh work|personal experiment-name [--dry-run]"
shift 2
load_profile "$profile"
target=$(experiment_machine_name "$experiment_name")

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DEV_DRY_RUN=1 ;;
    *) orb_usage_error "Unknown clone option: $1" ;;
  esac
  shift
done
export DEV_DRY_RUN
experiment_memory_mib=$(size_to_mib "$DEV_EXPERIMENT_MEMORY")
require_orbctl

if [ "$DEV_DRY_RUN" -eq 0 ]; then
  machine_exists "$DEV_MACHINE_NAME" || orb_die "Primary machine does not exist: $DEV_MACHINE_NAME"
  ! machine_exists "$target" || orb_die "Experiment machine already exists: $target"
fi

orb_log "Cloning $DEV_MACHINE_NAME to disposable machine $target"
run_orbctl clone "$DEV_MACHINE_NAME" "$target"
run_orbctl config set "machine.$target.memory_mib" "$experiment_memory_mib"
# Keep the inherited disk ceiling: a populated primary may already exceed a
# smaller limit, while OrbStack's copy-on-demand clone avoids eager duplication.
run_orbctl start "$target"
