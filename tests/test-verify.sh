#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-lib.sh
. "$SCRIPT_DIR/test-lib.sh"
# shellcheck source=bootstrap/verify-lib.sh
. "$TEST_ROOT/bootstrap/verify-lib.sh"

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

printf 'verification helper tests passed (%d assertions)\n' "$test_count"
