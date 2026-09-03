#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=orb/lib.sh
. "$SCRIPT_DIR/lib.sh"

profile=${1:-}
[ -n "$profile" ] || orb_usage_error "Usage: provision.sh work|personal [--dry-run] [--skip-ai]"
shift
load_profile "$profile"

skip_ai=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DEV_DRY_RUN=1 ;;
    --skip-ai) skip_ai=1 ;;
    *) orb_usage_error "Unknown provision option: $1" ;;
  esac
  shift
done
export DEV_DRY_RUN
require_orbctl

restart_if_required() {
  reboot_required=0
  if [ "$DEV_DRY_RUN" -eq 1 ]; then
    print_command orbctl run -m "$DEV_MACHINE_NAME" test -f /var/run/reboot-required
  elif orbctl run -m "$DEV_MACHINE_NAME" test -f /var/run/reboot-required; then
    reboot_required=1
  fi

  if [ "$reboot_required" -eq 1 ]; then
    orb_log "Restarting $DEV_MACHINE_NAME after Ubuntu package upgrades"
    run_orbctl restart "$DEV_MACHINE_NAME"
    run_orbctl run -m "$DEV_MACHINE_NAME" cloud-init status --wait
  fi
}

if [ "$DEV_DRY_RUN" -eq 0 ] && ! machine_exists "$DEV_MACHINE_NAME"; then
  orb_die "Machine does not exist: $DEV_MACHINE_NAME"
fi

orb_log "Waiting for cloud-init in $DEV_MACHINE_NAME"
run_orbctl run -m "$DEV_MACHINE_NAME" cloud-init status --wait
restart_if_required

bootstrap_args=(--profile "$profile")
if [ "$skip_ai" -eq 1 ]; then
  bootstrap_args+=(--skip-ai)
fi

orb_log "Running the generic Ubuntu bootstrap in $DEV_MACHINE_NAME"
run_orbctl run -m "$DEV_MACHINE_NAME" -p \
  bash "$DEV_MACHINE_ROOT/bootstrap/bootstrap.sh" "${bootstrap_args[@]}"
restart_if_required

# The guest shell must expand HOME when checking the Ubuntu checkout.
# shellcheck disable=SC2016
if [ "$DEV_DRY_RUN" -eq 1 ] \
  || ! orbctl run -m "$DEV_MACHINE_NAME" sh -c 'test -d "$HOME/code/dev-machine/.git"'; then
  orb_log "Seeding the provisioning repository in $DEV_MACHINE_NAME:~/code/dev-machine"
  # The guest shell must expand the translated source argument and Ubuntu HOME.
  # shellcheck disable=SC2016
  run_orbctl run -m "$DEV_MACHINE_NAME" -p \
    sh -c 'rsync -a "$1/." "$HOME/code/dev-machine/"' sh "$DEV_MACHINE_ROOT/"
else
  orb_log "Leaving the existing Ubuntu checkout unchanged: ~/code/dev-machine"
fi
