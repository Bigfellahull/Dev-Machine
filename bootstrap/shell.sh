#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"

log "Installing shell, tmux and non-identity Git configuration"
install_user_file \
  "$DEV_MACHINE_ROOT/config/shell/dev-machine.sh" \
  "$HOME/.config/dev-machine/shell.sh"
install_user_file \
  "$DEV_MACHINE_ROOT/config/tmux/tmux.conf" \
  "$HOME/.tmux.conf"
install_user_file \
  "$DEV_MACHINE_ROOT/config/starship.toml" \
  "$HOME/.config/starship.toml"
install_user_file \
  "$DEV_MACHINE_ROOT/config/git/dev-machine.inc" \
  "$HOME/.config/git/dev-machine.inc"

runtime_root="$HOME/.local/share/dev-machine"
mkdir -p "$runtime_root"
docker_rsync_args=(-a --delete --delete-excluded)
for engine in postgres mssql redis; do
  case " $DEV_MACHINE_DB_ENGINES " in
    *" $engine "*) ;;
    *) docker_rsync_args+=(--exclude "/$engine/") ;;
  esac
done
rsync "${docker_rsync_args[@]}" "$DEV_MACHINE_ROOT/docker/" "$runtime_root/docker/"
printf '%s\n' "$DEV_MACHINE_DB_ENGINES" >"$runtime_root/docker/enabled-engines"
install_user_file "$DEV_MACHINE_ROOT/bin/db" "$HOME/.local/bin/db" 0755
install_user_file \
  "$DEV_MACHINE_ROOT/bin/local-dev-tls" \
  "$HOME/.local/bin/local-dev-tls" \
  0755

printf '%s\n' "$DEV_MACHINE_PROFILE" >"$HOME/.config/dev-machine/profile"
# The literal line must expand HOME when a future shell reads .bashrc.
# shellcheck disable=SC2016
ensure_line "$HOME/.bashrc" '[ -r "$HOME/.config/dev-machine/shell.sh" ] && . "$HOME/.config/dev-machine/shell.sh"'

git_include="$HOME/.config/git/dev-machine.inc"
if ! git config --global --get-all include.path 2>/dev/null | grep -Fqx "$git_include"; then
  git config --global --add include.path "$git_include"
fi

"$HOME/.local/bin/mise" exec -- git lfs install --skip-repo

info "Git user.name and user.email were intentionally left unset."
