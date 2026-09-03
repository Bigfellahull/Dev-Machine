#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=orb/lib.sh
. "$ROOT/orb/lib.sh"

profile=${1:-}
[ -n "$profile" ] || orb_usage_error "Usage: export-machine.sh work|personal"
load_profile "$profile"

[ "$(uname -s)" = Darwin ] || orb_die "Machine exports must run on the macOS host."
require_orbctl
machine_exists "$DEV_MACHINE_NAME" || orb_die "Machine does not exist: $DEV_MACHINE_NAME"

external_root=$("$ROOT/scripts/backup/require-external.sh")
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
destination="$DEV_MACHINE_NAME-$timestamp.tar.zst"
manifest="$destination.manifest"
partial_destination="$destination.partial"

enter_machine_export_directory "$external_root" \
  || orb_die "External export directory is unavailable or unsafe."
[ ! -e "$destination" ] && [ ! -L "$destination" ] \
  || orb_die "Refusing to replace existing export: $PWD/$destination"
[ ! -e "$manifest" ] && [ ! -L "$manifest" ] \
  || orb_die "Refusing to replace existing export manifest: $PWD/$manifest"
[ ! -e "$partial_destination" ] && [ ! -L "$partial_destination" ] \
  || orb_die "Refusing to replace partial export: $PWD/$partial_destination"
command -v shasum >/dev/null 2>&1 || orb_die "shasum is required to verify exports."
verified_root=$("$ROOT/scripts/backup/require-external.sh")
[ "$verified_root" = "$external_root" ] \
  || orb_die "External volume changed while preparing the export."
orb_log "Exporting $DEV_MACHINE_NAME to $PWD/$destination"
orbctl export "$DEV_MACHINE_NAME" "$partial_destination"
[ -f "$partial_destination" ] && [ ! -L "$partial_destination" ] \
  || orb_die "OrbStack did not create a regular export archive."
digest=$(archive_sha256 "$partial_destination") \
  || orb_die "Could not hash the export archive."
mv "$partial_destination" "$destination"
write_export_manifest "$destination" "$digest" \
  || orb_die "Could not write the export manifest: $PWD/$manifest"
printf '%s\n%s\n' "$PWD/$destination" "$PWD/$manifest"
