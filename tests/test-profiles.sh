#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-lib.sh
. "$SCRIPT_DIR/test-lib.sh"

fixture=$(mktemp -d "${TMPDIR:-/tmp}/dev-machine-profiles.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/mocks" "$fixture/home/.local/bin"
export TEST_MOCK_MISE="$fixture/mocks/mise" TEST_TOOL_LOG="$fixture/tools.log"
export TEST_INSTALLED_TOOLS="$fixture/installed-tools"
touch "$TEST_INSTALLED_TOOLS" "$TEST_TOOL_LOG"
export TEST_BOOTSTRAP_ROOT="$fixture/repo"
mkdir -p "$TEST_BOOTSTRAP_ROOT/config"
cp -R "$TEST_ROOT/bootstrap" "$TEST_ROOT/profiles" "$TEST_BOOTSTRAP_ROOT/"
cp -R "$TEST_ROOT/config/ai" "$TEST_ROOT/config/mise" "$TEST_ROOT/config/dotnet" "$TEST_BOOTSTRAP_ROOT/config/"
cp "$TEST_ROOT/config/rust-toolchain" "$TEST_BOOTSTRAP_ROOT/config/"

cat >"$fixture/bash-env" <<'EOF'
. "$TEST_BOOTSTRAP_ROOT/bootstrap/lib.sh"
# Stub the platform boundary; package managers below are separate mocks.
require_target_ubuntu() { :; }
EOF
cat >"$fixture/mocks/curl" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    cat >"$2" <<'INSTALL'
#!/usr/bin/env sh
install -m 0755 "$TEST_MOCK_MISE" "$MISE_INSTALL_PATH"
INSTALL
    exit 0
  fi
  shift
done
exit 1
EOF
cat >"$TEST_MOCK_MISE" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_TOOL_LOG"
case "$*" in
  'activate bash') printf ':\n' ;;
  'exec -- dotnet tool list --global') cat "$TEST_INSTALLED_TOOLS" ;;
esac
EOF
chmod +x "$fixture/mocks/curl" "$TEST_MOCK_MISE"
for cli in codex claude grok; do
  printf '#!/bin/sh\nexit 0\n' >"$fixture/mocks/$cli"
  chmod +x "$fixture/mocks/$cli"
done
cp "$TEST_ROOT/tests/fixtures/claude" "$fixture/mocks/claude"
chmod +x "$fixture/mocks/claude"

# Execute the real module with isolated user state and mocked external installers.
run_module() {
  local profile=$1 module=$2
  local work=0
  [ "$profile" != work ] || work=1
  env HOME="$fixture/home" BASH_ENV="$fixture/bash-env" \
    DEV_MACHINE_PYTHON="$(command -v python3)" \
    PATH="$fixture/mocks:$PATH" DEV_MACHINE_PROFILE="$profile" \
    DEV_INSTALL_WORK_TOOLS="$work" DEV_INSTALL_DOTNET_WASM_TOOLS="$work" \
    "$TEST_BOOTSTRAP_ROOT/bootstrap/$module.sh" >/dev/null
}

run_module work runtimes
[ -f "$fixture/home/.config/mise/conf.d/dev-machine-work.toml" ] || test_fail "work tools not installed"
[ ! -e "$fixture/home/.config/mise/conf.d/dev-machine-personal.toml" ] || test_fail "Railway config leaked into work"
assert_contains "$(cat "$TEST_TOOL_LOG")" 'exec -- dotnet tool install --global Microsoft.SqlPackage'
assert_contains "$(cat "$TEST_TOOL_LOG")" 'uninstall --all railway'
assert_contains "$(cat "$TEST_TOOL_LOG")" 'exec -- rustup toolchain install 1.98.0 --profile minimal'
assert_contains "$(cat "$TEST_TOOL_LOG")" 'exec dotnet@10.0.400 -- dotnet workload install wasm-tools --version 10.0.400.1'
assert_contains "$(cat "$fixture/home/.config/mise/conf.d/dev-machine-work.toml")" 'dotnet = ["10.0.400", "10"]'
run_module work ai-tools
[ ! -e "$fixture/home/.agents/skills/use-railway" ] || test_fail "Railway skill leaked into work"

printf 'microsoft.sqlpackage 1.0 sqlpackage\nmicrosoft.artifacts.credentialprovider.nuget.tool 1.0 provider\n' >"$TEST_INSTALLED_TOOLS"
: >"$TEST_TOOL_LOG"
run_module work runtimes
assert_contains "$(cat "$TEST_TOOL_LOG")" 'exec -- dotnet tool update --global Microsoft.SqlPackage'
run_module personal runtimes
[ ! -e "$fixture/home/.config/mise/conf.d/dev-machine-work.toml" ] || test_fail "work config retained on personal"
cmp "$TEST_ROOT/config/mise/personal.toml" "$fixture/home/.config/mise/conf.d/dev-machine-personal.toml"
assert_contains "$(cat "$TEST_TOOL_LOG")" 'exec -- dotnet tool uninstall --global Microsoft.SqlPackage'
run_module personal ai-tools
diff -qr "$TEST_ROOT/config/ai/skills/use-railway" "$fixture/home/.agents/skills/use-railway" >/dev/null
for agent in .claude .codex; do
  [ "$(readlink "$fixture/home/$agent/skills/use-railway")" = '../../.agents/skills/use-railway' ] \
    || test_fail "Railway skill is not shared"
done
run_module personal ai-tools
run_module work ai-tools
[ ! -e "$fixture/home/.agents/skills/use-railway" ] || test_fail "Railway skill retained on work"
[ ! -L "$fixture/home/.codex/skills/use-railway" ] || test_fail "Railway link retained on work"

run_module personal ai-tools
printf '\nLocal customisation\n' >>"$fixture/home/.agents/skills/use-railway/SKILL.md"
assert_fails run_module work ai-tools
assert_contains "$(tail -1 "$fixture/home/.agents/skills/use-railway/SKILL.md")" 'Local customisation'
[ -L "$fixture/home/.codex/skills/use-railway" ] || test_fail "rejected cleanup changed skill links"

mkdir -p "$fixture/home/.local/share/dev-machine/tesseract/bin"
touch "$fixture/home/.local/share/dev-machine/tesseract/.dev-machine"
ln -s "$fixture/home/.local/share/dev-machine/tesseract/bin/tesseract" "$fixture/home/.local/bin/tesseract"
run_module personal ocr
[ ! -L "$fixture/home/.local/bin/tesseract" ] || test_fail "OCR command retained on personal"
[ ! -e "$fixture/home/.local/share/dev-machine/tesseract" ] || test_fail "OCR runtime retained on personal"
printf 'unmanaged\n' >"$fixture/home/.local/bin/tesseract"
assert_fails run_module personal ocr
assert_contains "$(cat "$fixture/home/.local/bin/tesseract")" unmanaged

printf 'profile convergence tests passed (%d assertions)\n' "$test_count"
