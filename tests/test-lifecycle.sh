#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-lib.sh
. "$SCRIPT_DIR/test-lib.sh"
cd "$TEST_ROOT"

output=$(bin/dev create work --dry-run)
assert_contains "$output" "ubuntu:resolute work-dev"
assert_contains "$output" "--arch arm64"
assert_contains "$output" "--memory 24G"
assert_contains "$output" "cloud-init status --wait"
assert_contains "$output" "/var/run/reboot-required"
assert_contains "$output" "bootstrap/bootstrap.sh --profile work"
assert_not_contains "$output" "work-dev -- cloud-init"
assert_not_contains "$output" "work-dev -p -- bash"
assert_contains "$output" 'rsync\ -a'
assert_contains "$output" "\$1/."
assert_contains "$output" 'HOME/code/dev-machine/'
assert_not_contains "$output" "ubuntu:latest"

output=$(bin/dev clone personal risky-sdk --dry-run)
assert_contains "$output" "orbctl clone personal-dev personal-exp-risky-sdk"
assert_contains "$output" "machine.personal-exp-risky-sdk.memory_mib 8192"
assert_contains "$output" "orbctl start personal-exp-risky-sdk"

output=$(bin/dev destroy-experiment work risky-sdk --dry-run)
assert_contains "$output" "orbctl delete --force work-exp-risky-sdk"
assert_not_contains "$output" "--all"
assert_not_contains "$output" "*"

output=$(bin/dev rebuild personal --yes --skip-ai --dry-run)
assert_contains "$output" "orbctl delete --force personal-dev"
assert_contains "$output" "ubuntu:resolute personal-dev"
assert_contains "$output" "--profile personal --skip-ai"

assert_fails bin/dev clone work 'Bad_Name' --dry-run
assert_fails bin/dev destroy-experiment work '-' --dry-run
assert_fails bin/dev destroy-experiment work 'name*' --dry-run
if output=$(DEV_MACHINE_MEMORY=bad bin/dev rebuild work --yes --dry-run 2>&1); then
  test_fail 'rebuild accepted invalid replacement resources'
fi
assert_not_contains "$output" 'orbctl delete'
assert_not_contains "$output" 'orbctl create'

if output=$(DEV_EXPERIMENT_MEMORY=bad bin/dev clone work invalid-memory --dry-run 2>&1); then
  test_fail 'clone accepted invalid replacement resources'
fi
assert_not_contains "$output" 'orbctl clone'
assert_not_contains "$output" 'orbctl config set'

assert_fails env DEV_MACHINE_DISK=0G bin/dev create personal --dry-run
assert_fails env DEV_MACHINE_CPUS=0 bin/dev rebuild personal --yes --dry-run
assert_fails env DEV_MACHINE_MEMORY=08G bin/dev create personal --dry-run
assert_fails env DEV_MACHINE_MEMORY=9999999999G bin/dev create personal --dry-run
if output=$(DEV_MACHINE_MEMORY=08G bin/dev rebuild work --yes --dry-run 2>&1); then
  test_fail 'rebuild accepted a non-canonical replacement resource'
fi
assert_not_contains "$output" 'orbctl delete'
assert_not_contains "$output" 'orbctl create'
assert_fails env DEV_MACHINE_CPUS=01 bin/dev rebuild personal --yes --dry-run
assert_fails env DEV_MACHINE_CPUS=9999999999 bin/dev rebuild personal --yes --dry-run
assert_fails env DEV_EXTERNAL_VOLUME=dev-machine-definitely-not-mounted \
  scripts/backup/require-external.sh
assert_fails env DEV_EXTERNAL_VOLUME=.. scripts/backup/require-external.sh
assert_fails env DEV_EXTERNAL_VOLUME=../tmp scripts/backup/require-external.sh

# shellcheck source=scripts/backup/require-external.sh
. scripts/backup/require-external.sh
assert_fails valid_external_volume_name '../tmp'
external_volume_properties_are_safe /Volumes/DevArchive /Volumes/DevArchive \
  false true true || test_fail 'external disk metadata was rejected'
test_count=$((test_count + 1))
printf 'ok %d - accepts external disk metadata\n' "$test_count"
assert_fails external_volume_properties_are_safe /Volumes/DevArchive \
  /Volumes/Other false true true
assert_fails external_volume_properties_are_safe /Volumes/DevArchive \
  /Volumes/DevArchive true true true
assert_fails external_volume_properties_are_safe /Volumes/DevArchive \
  /Volumes/DevArchive false false true
assert_fails external_volume_properties_are_safe /Volumes/DevArchive \
  /Volumes/DevArchive false true false

# shellcheck source=orb/lib.sh
. orb/lib.sh
archive_test_directory=$(mktemp -d "${TMPDIR:-/tmp}/dev-machine-archive-test.XXXXXX")
trap 'rm -R "$archive_test_directory"' EXIT
mkdir "$archive_test_directory/external" "$archive_test_directory/internal"
ln -s "$archive_test_directory/internal" "$archive_test_directory/external/orbstack"
if (enter_machine_export_directory "$archive_test_directory/external"); then
  test_fail 'machine export directory followed an escaping symlink'
fi
test_count=$((test_count + 1))
printf 'ok %d - rejects symlinked export directory components\n' "$test_count"

archive="$archive_test_directory/work-dev-test.tar.zst"
printf 'archive fixture\n' >"$archive"
DEV_MACHINE_PROFILE=work
DEV_MACHINE_NAME=work-dev
DEV_ORB_DISTRO=ubuntu:resolute
DEV_ORB_ARCH=arm64
write_export_manifest "$archive" || test_fail 'could not write export manifest fixture'
verify_export_manifest "$archive" || test_fail 'valid export manifest was rejected'
test_count=$((test_count + 1))
printf 'ok %d - validates matching export provenance\n' "$test_count"
DEV_MACHINE_PROFILE=personal
DEV_MACHINE_NAME=personal-dev
assert_fails verify_export_manifest "$archive"
DEV_MACHINE_PROFILE=work
DEV_MACHINE_NAME=work-dev
printf 'tampered\n' >>"$archive"
assert_fails verify_export_manifest "$archive"
rm "$archive.manifest"
assert_fails verify_export_manifest "$archive"

printf 'archive fixture\n' >"$archive"
chmod() { return 9; }
if write_export_manifest "$archive"; then
  test_fail 'manifest publication hid a chmod failure'
fi
unset -f chmod
[ ! -e "$archive.manifest" ] || test_fail 'failed manifest was published'
if find "$archive_test_directory" -maxdepth 1 -name '*.manifest.tmp.*' -print -quit \
  | grep -q .; then
  test_fail 'failed manifest temporary file was retained'
fi
test_count=$((test_count + 1))
printf 'ok %d - manifest publication fails cleanly\n' "$test_count"

printf 'lifecycle tests passed (%d assertions)\n' "$test_count"
