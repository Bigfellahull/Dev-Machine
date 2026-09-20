#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-lib.sh
. "$SCRIPT_DIR/test-lib.sh"

fixture=$(mktemp -d "${TMPDIR:-/tmp}/dev-machine-shell.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/home/.local/share/blesh"

cat >"$fixture/home/.local/share/blesh/ble.sh" <<'EOF'
printf 'ble-load %s\n' "$*"
BLE_VERSION=test
ble-import() { printf 'ble-import %s\n' "$*"; }
ble-face() { :; }
ble-attach() { printf 'ble-attach\n'; }
EOF

cat >"$fixture/session.sh" <<'EOF'
fzf() { printf '%s\n' 'printf "fzf-direct\n"'; }
starship() { printf '%s\n' 'printf "starship\n"'; }
zoxide() { printf '%s\n' ':'; }
bat() { :; }
source "$TEST_ROOT/config/shell/dev-machine.sh"
printf 'session-ready\n'
EOF

# shellcheck disable=SC2016
interactive_output=$(env HOME="$fixture/home" bash --noprofile --norc -ic \
  'source "$1"' bash "$fixture/session.sh" 2>"$fixture/stderr")
expected_output=$(cat <<'EOF'
ble-load --attach=none
ble-import -d integration/fzf-completion
ble-import -d integration/fzf-key-bindings
starship
ble-attach
session-ready
EOF
)
[ "$interactive_output" = "$expected_output" ] \
  || test_fail "interactive startup did not initialise ble.sh, fzf and Starship in order"

noninteractive_output=$(env HOME="$fixture/home" bash --noprofile --norc \
  "$fixture/session.sh")
assert_not_contains "$noninteractive_output" ble-
assert_contains "$noninteractive_output" session-ready

rm "$fixture/home/.local/share/blesh/ble.sh"
# shellcheck disable=SC2016
fallback_output=$(env HOME="$fixture/home" bash --noprofile --norc -ic \
  'source "$1"' bash "$fixture/session.sh" 2>"$fixture/stderr")
assert_contains "$fallback_output" fzf-direct
assert_not_contains "$fallback_output" ble-
assert_contains "$fallback_output" session-ready

printf 'Shell integration tests passed\n'
