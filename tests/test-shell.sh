#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-lib.sh
. "$SCRIPT_DIR/test-lib.sh"
# shellcheck source=bootstrap/lib.sh
. "$TEST_ROOT/bootstrap/lib.sh"
# shellcheck source=bootstrap/verify-lib.sh
. "$TEST_ROOT/bootstrap/verify-lib.sh"

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

for startup in none .profile .bash_login .bash_profile profile-with-bashrc; do
  startup_home="$fixture/$startup"
  mkdir -p "$startup_home/.local/bin" "$startup_home/tool-bin"
  case "$startup" in
    none) expected_profile=.profile ;;
    profile-with-bashrc)
      expected_profile=.profile
      # shellcheck disable=SC2016
      printf '. "$HOME/.bashrc"\n' >"$startup_home/.profile"
      ;;
    *)
      expected_profile=$startup
      printf 'export USER_PROFILE_VALUE=preserved\n' >"$startup_home/.profile"
      printf 'export USER_PROFILE_VALUE=preserved\n' >"$startup_home/$startup"
      ;;
  esac

  cat >"$startup_home/.local/bin/mise" <<'EOF'
#!/bin/bash
[ "$*" = 'activate bash' ] || exit 1
cat <<'ACTIVATE'
export PATH="$HOME/tool-bin:$PATH"
printf 'activated\n' >>"$HOME/activation.log"
ACTIVATE
EOF
  cat >"$startup_home/tool-bin/dotnet" <<'EOF'
#!/bin/sh
printf '10.0.401\n'
EOF
  chmod +x "$startup_home/.local/bin/mise" "$startup_home/tool-bin/dotnet"

  # An inherited marker must not conceal a missing login hook.
  HOME="$startup_home" DEV_MACHINE_SHELL_LOADED=1 \
    assert_fails bash_login_loads_environment
  HOME="$startup_home" install_bash_startup
  [ "$(HOME="$startup_home" bash_login_file)" = "$startup_home/$expected_profile" ] \
    || test_fail "bootstrap changed login file precedence"
  cp "$startup_home/$expected_profile" "$startup_home/profile-before"
  cp "$startup_home/.bashrc" "$startup_home/bashrc-before"
  HOME="$startup_home" install_bash_startup
  cmp "$startup_home/profile-before" "$startup_home/$expected_profile"
  cmp "$startup_home/bashrc-before" "$startup_home/.bashrc"

  # shellcheck disable=SC2016
  login_output=$(env HOME="$startup_home" PATH=/usr/bin:/bin \
    /bin/bash -lic 'dotnet --version; printf "%s\n" "${USER_PROFILE_VALUE:-}"' 2>"$fixture/stderr")
  assert_contains "$login_output" '10.0.401'
  case "$startup" in
    .profile|.bash_login|.bash_profile) assert_contains "$login_output" preserved ;;
  esac
  [ "$(wc -l <"$startup_home/activation.log" | tr -d ' ')" = 1 ] \
    || test_fail "login startup activated mise more than once"
  HOME="$startup_home" bash_login_loads_environment 2>"$fixture/stderr"

  nonlogin_output=$(env HOME="$startup_home" PATH=/usr/bin:/bin \
    /bin/bash -ic 'dotnet --version' 2>"$fixture/stderr")
  assert_contains "$nonlogin_output" '10.0.401'
done

# A shared .profile must remain safe for non-interactive Bash and POSIX shells.
# shellcheck disable=SC2016
env HOME="$fixture/none" /bin/bash -lc \
  'test -z "${DEV_MACHINE_SHELL_LOADED:-}"' 2>"$fixture/stderr"
# shellcheck disable=SC2016
env HOME="$fixture/none" /bin/sh -c '. "$HOME/.profile"'

printf 'Shell integration tests passed\n'
