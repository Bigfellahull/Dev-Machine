#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
require_target_ubuntu

swap_file=/swapfile
swap_size=8G
oom_config_source="$DEV_MACHINE_ROOT/config/systemd/user.conf.d/90-dev-machine-oom.conf"
oom_config_target=/etc/systemd/user.conf.d/90-dev-machine-oom.conf

log "Configuring memory resilience"
for command_name in blkid fallocate mkswap swapon systemctl; do
  require_command "$command_name"
done

active_swap=$(swapon --show=NAME --noheadings --raw 2>/dev/null || true)
if [ -z "$active_swap" ]; then
  if [ -L "$swap_file" ] || { [ -e "$swap_file" ] && [ ! -f "$swap_file" ]; }; then
    die "Refusing to replace non-regular swap path: $swap_file"
  fi

  if [ -f "$swap_file" ]; then
    if ! sudo blkid -p -s TYPE -o value "$swap_file" 2>/dev/null | grep -Fqx swap; then
      die "Refusing to overwrite an existing non-swap file: $swap_file"
    fi
    info "Activating the existing swap file: $swap_file"
  else
    info "Creating a $swap_size swap file: $swap_file"
    sudo fallocate -l "$swap_size" "$swap_file"
    sudo chmod 0600 "$swap_file"
    sudo mkswap "$swap_file" >/dev/null
  fi

  sudo chmod 0600 "$swap_file"
  sudo swapon "$swap_file"
else
  info "Active swap already exists; leaving it unchanged."
fi

active_swap=$(swapon --show=NAME --noheadings --raw 2>/dev/null || true)
if printf '%s\n' "$active_swap" | grep -Fqx "$swap_file"; then
  sudo chmod 0600 "$swap_file"
  if ! awk '$1 == "/swapfile" && $3 == "swap" { found=1 } END { exit !found }' /etc/fstab; then
    printf '%s\n' "$swap_file none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
  fi
fi

sudo install -D -m 0644 "$oom_config_source" "$oom_config_target"
if ! oom_policy=$(systemctl --user show --property=DefaultOOMPolicy --value); then
  die "Cannot read the user systemd manager OOM policy."
fi
if [ "$oom_policy" != continue ]; then
  systemctl --user daemon-reexec
fi
if [ "$(systemctl --user show --property=DefaultOOMPolicy --value)" != continue ]; then
  die "The user systemd manager did not apply DefaultOOMPolicy=continue."
fi

info "New tmux panes will survive an OOM kill of one process in their scope."
