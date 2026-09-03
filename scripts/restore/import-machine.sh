#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=orb/lib.sh
. "$ROOT/orb/lib.sh"

profile=${1:-}
archive=${2:-}
[ -n "$profile" ] && [ -n "$archive" ] \
  || orb_usage_error "Usage: import-machine.sh work|personal ARCHIVE.tar.zst"
load_profile "$profile"

[ "$(uname -s)" = Darwin ] || orb_die "Machine imports must run on the macOS host."
require_orbctl
[ -f "$archive" ] && [ ! -L "$archive" ] \
  || orb_die "Archive must be a readable regular file, not a symlink: $archive"
archive_directory=$(cd "$(dirname "$archive")" && pwd -P) \
  || orb_die "Archive directory is unavailable: $archive"
archive="$archive_directory/${archive##*/}"
command -v shasum >/dev/null 2>&1 || orb_die "shasum is required to verify imports."
verify_export_manifest "$archive" \
  || orb_die "Export provenance is missing or does not match the selected profile and archive."
! machine_exists "$DEV_MACHINE_NAME" || orb_die "Refusing to replace existing machine: $DEV_MACHINE_NAME"

orb_log "Importing exact target $DEV_MACHINE_NAME from $archive"
orbctl import -n "$DEV_MACHINE_NAME" "$archive"
