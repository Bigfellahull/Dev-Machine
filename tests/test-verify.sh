#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-lib.sh
. "$SCRIPT_DIR/test-lib.sh"
# shellcheck source=bootstrap/verify-lib.sh
. "$TEST_ROOT/bootstrap/verify-lib.sh"
# shellcheck source=bootstrap/lib.sh
. "$TEST_ROOT/bootstrap/lib.sh"

empty_version() {
  return 0
}

normal_version() {
  printf 'tool 1.2.3\nmore output\n'
}

assert_fails capture_version empty_version
output=$(capture_version normal_version)
assert_contains "$output" 'tool 1.2.3'
assert_not_contains "$output" 'more output'

mock_directory=$(mktemp -d "${TMPDIR:-/tmp}/dev-machine-verify-test.XXXXXX")
trap 'rm -R "$mock_directory"' EXIT
cat >"$mock_directory/sqlcmd" <<'EOF'
#!/usr/bin/env bash
case "${SQLCMD_TEST_MODE:-normal}" in
  fail) exit 42 ;;
  malformed) printf 'sqlcmd without a version field\n' ;;
  normal) printf 'Version: 1.8.0\n' ;;
esac
EOF
chmod +x "$mock_directory/sqlcmd"

PATH="$mock_directory:$PATH" SQLCMD_TEST_MODE=fail assert_fails sqlcmd_version
PATH="$mock_directory:$PATH" SQLCMD_TEST_MODE=malformed assert_fails sqlcmd_version
output=$(PATH="$mock_directory:$PATH" SQLCMD_TEST_MODE=normal sqlcmd_version)
assert_contains "$output" '1.8.0'

cat >"$mock_directory/ffmpeg" <<'EOF'
#!/usr/bin/env bash
for encoder in png mjpeg libvpx libvpx-vp9 libvorbis libmp3lame; do
  [ "$encoder" != "${MISSING_ENCODER:-}" ] || continue
  printf ' V..... %s description\n' "$encoder"
done
EOF
chmod +x "$mock_directory/ffmpeg"
PATH="$mock_directory:$PATH" ffmpeg_encoders_available
for encoder in png mjpeg libvpx libvpx-vp9 libvorbis libmp3lame; do
  PATH="$mock_directory:$PATH" MISSING_ENCODER="$encoder" assert_fails ffmpeg_encoders_available
done

cat >"$mock_directory/railway" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${TEST_RAILWAY_VERSION:-railway 5.44.0}"
EOF
chmod +x "$mock_directory/railway"
PATH="$mock_directory:$PATH" railway_supports_hosted_mcp
for version in 'railway 5.43.9' 'railway 4.99.0' 'unrecognised output'; do
  PATH="$mock_directory:$PATH" TEST_RAILWAY_VERSION="$version" assert_fails railway_supports_hosted_mcp
done
PATH="$mock_directory:$PATH" TEST_RAILWAY_VERSION='railway 6.0.0' railway_supports_hosted_mcp

mkdir -p "$mock_directory/home/.local/bin" "$mock_directory/project"
printf '{"sdk":{"version":"10.0.999","rollForward":"disable"}}\n' \
  >"$mock_directory/project/global.json"
cat >"$mock_directory/home/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
set -eu
[ "${MISE_AUTO_INSTALL:-}" = false ]
[ "$1 $2 $3 $4" = 'exec dotnet@10.0.400 -- dotnet' ]
shift 4
python3 - <<'PY'
import json
from pathlib import Path

sdk = json.loads(Path("global.json").read_text())["sdk"]
assert sdk["version"] == "10.0.400"
assert sdk["rollForward"] == "disable"
assert "workloadVersion" not in sdk
PY
[ "${TEST_WORK_DOTNET_FAIL:-0}" = 0 ] || exit 42
printf '%s\n' "$*"
EOF
chmod +x "$mock_directory/home/.local/bin/mise"
(
  cd "$mock_directory/project"
  export HOME="$mock_directory/home"
  original_directory=$PWD
  work_dotnet --version >/dev/null
  [ "$PWD" = "$original_directory" ] || test_fail "work SDK selection changed the caller's directory"
  output=$(work_dotnet workload install wasm-tools --version 10.0.400.1)
  assert_contains "$output" 'workload install wasm-tools --version 10.0.400.1'
  output=$(work_dotnet workload --version)
  assert_contains "$output" 'workload --version'
  output=$(work_dotnet workload list)
  assert_contains "$output" 'workload list'
  TEST_WORK_DOTNET_FAIL=1 assert_fails work_dotnet --version
  DEV_MACHINE_ROOT="$mock_directory/missing" assert_fails work_dotnet --version
  printf 'verification helper tests passed (%d assertions)\n' "$test_count"
)
