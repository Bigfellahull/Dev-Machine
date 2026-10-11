#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
# shellcheck source=bootstrap/verify-lib.sh
. "$SCRIPT_DIR/verify-lib.sh"
require_target_ubuntu

log "Configuring disk-backed temporary storage"
backing=/var/lib/dev-machine/tmp
unit=dev-machine-tmp.service
for command_name in findmnt install stat systemctl; do
  require_command "$command_name"
done
for directory in /var/lib/dev-machine "$backing"; do
  [ ! -L "$directory" ] || die "Refusing a symlinked temporary-storage path: $directory"
done
sudo install -d -o root -g root -m 0755 /var/lib/dev-machine
sudo install -d -o root -g root -m 1777 "$backing"
case "$(findmnt -n -o FSTYPE --target "$backing")" in
  ''|tmpfs|ramfs) die "Temporary storage must reside on a disk filesystem: $backing" ;;
esac
sudo install -m 0644 "$DEV_MACHINE_ROOT/config/systemd/$unit" "/etc/systemd/system/$unit"
sudo systemctl daemon-reload
sudo systemctl enable "$unit"

# Replacing /tmp live would hide sockets and files belonging to running clients.
if [ "$(stat -c %d /tmp)" != "$(stat -c %d "$backing")" ] \
  || [ "$(stat -c %i /tmp)" != "$(stat -c %i "$backing")" ] \
  || ! temporary_storage_mount_options_valid /tmp; then
  sudo touch /run/reboot-required
  warn "Restart required to activate disk-backed /tmp. Existing /tmp contents are not migrated by bootstrap."
else
  info "/tmp already uses the managed disk-backed directory."
fi
