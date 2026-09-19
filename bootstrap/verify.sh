#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
# shellcheck source=bootstrap/verify-lib.sh
. "$SCRIPT_DIR/verify-lib.sh"

failures=0
warnings=0
skip_ai=0

usage() {
  cat <<'USAGE'
Usage: verify.sh [--skip-ai]

Verify the provisioned development environment. Use --skip-ai when the
bootstrap was intentionally run with the same option.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-ai) skip_ai=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown verification option: $1" ;;
  esac
  shift
done

managed_shell_config="$HOME/.config/dev-machine/shell.sh"
if [ -r "$managed_shell_config" ]; then
  # shellcheck disable=SC1090
  . "$managed_shell_config"
fi

pass() {
  printf 'PASS  %s\n' "$*"
}

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  failures=$((failures + 1))
}

verify_warn() {
  printf 'WARN  %s\n' "$*" >&2
  warnings=$((warnings + 1))
}

check_command() {
  command_name=$1
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "$command_name: $(command -v "$command_name")"
  else
    fail "$command_name is not installed or not on PATH"
  fi
}

check_version() {
  version_name=$1
  shift
  if version_output=$(capture_version "$@"); then
    pass "$version_name: $version_output"
  else
    fail "$version_name did not return a version"
  fi
}

check_managed_file() {
  source_file=$1
  target_file=$2
  description=$3

  if [ -f "$target_file" ] && cmp -s "$source_file" "$target_file"; then
    pass "$description"
  else
    fail "$description"
  fi
}

check_managed_directory() {
  source_directory=$1
  target_directory=$2
  description=$3

  if [ -d "$target_directory" ] && [ ! -L "$target_directory" ] \
    && diff -qr "$source_directory" "$target_directory" >/dev/null; then
    pass "$description"
  else
    fail "$description"
  fi
}

printf 'Development machine verification\n'
printf '================================\n'

profile=${DEV_MACHINE_PROFILE:-}
if [ -r "$HOME/.config/dev-machine/profile" ]; then
  installed_profile=$(cat "$HOME/.config/dev-machine/profile")
  case "$installed_profile" in
    work|personal)
      if [ -n "$profile" ] && [ "$profile" != "$installed_profile" ]; then
        fail "requested profile $profile does not match installed profile $installed_profile"
      fi
      profile=$installed_profile
      pass "machine profile is $profile"
      ;;
    *) fail "machine profile is invalid: $installed_profile" ;;
  esac
else
  fail "machine profile marker is missing"
fi

required_commands=(
  age
  bat
  bwrap
  curl
  db
  dotnet
  fd
  fzf
  gh
  git
  git-lfs
  go
  jq
  mise
  node
  openssl
  psql
  python
  rg
  socat
  sqlc
  starship
  tmux
  zoxide
  local-dev-tls
)
if [ "$profile" = work ]; then
  required_commands+=(
    az
    cargo
    ffmpeg
    gs
    pandoc
    pdftotext
    qpdf
    redis-cli
    rustc
    sqlcmd
    sqlpackage
    syft
    uv
    weasyprint
    tesseract
  )
elif [ "$profile" = personal ]; then
  required_commands+=(railway)
fi

for command_name in "${required_commands[@]}"; do
  check_command "$command_name"
done

if [ "$skip_ai" -eq 1 ]; then
  pass "AI CLI checks were intentionally skipped"
else
  for command_name in codex claude grok; do
    check_command "$command_name"
  done

  if "${DEV_MACHINE_PYTHON:-/usr/bin/python3}" "$SCRIPT_DIR/ai-config.py" verify --profile "$profile"; then
    pass "managed AI models, effort, safety settings and MCP registrations are current"
  else
    fail "managed AI configuration is incomplete or differs from bootstrap"
  fi
  if "${DEV_MACHINE_PYTHON:-/usr/bin/python3}" "$SCRIPT_DIR/ai-config.py" verify-plugins --profile "$profile"; then
    pass "approved Claude plugins are installed at user scope"
  else
    fail "approved Claude plugins or the required CLI version are missing"
  fi

  for config_file in \
    "$HOME/.codex/config.toml" \
    "$HOME/.codex/AGENTS.md" \
    "$HOME/.claude/settings.json" \
    "$HOME/.claude/CLAUDE.md" \
    "$HOME/.grok/config.toml" \
    "$HOME/.grok/sandbox.toml" \
    "$HOME/.grok/AGENTS.md"; do
    if [ -f "$config_file" ] && [ -r "$config_file" ]; then
      pass "AI CLI configuration exists: $config_file"
    else
      fail "AI CLI configuration is missing: $config_file"
    fi
  done

  check_managed_file \
    "$DEV_MACHINE_ROOT/config/ai/AGENTS.md" \
    "$HOME/.codex/AGENTS.md" \
    "Codex global instructions are current"
  check_managed_file \
    "$DEV_MACHINE_ROOT/config/ai/AGENTS.md" \
    "$HOME/.grok/AGENTS.md" \
    "Grok global instructions are current"
  check_managed_file \
    "$DEV_MACHINE_ROOT/config/ai/CLAUDE.md" \
    "$HOME/.claude/CLAUDE.md" \
    "Claude global instructions are current"
  check_managed_directory \
    "$DEV_MACHINE_ROOT/config/ai/skills/codebase-sweep" \
    "$HOME/.agents/skills/codebase-sweep" \
    "shared codebase-sweep skill is current"
  check_managed_directory \
    "$DEV_MACHINE_ROOT/config/ai/skills/collab" \
    "$HOME/.agents/skills/collab" \
    "shared collab skill is current"
  managed_skills=(codebase-sweep collab)
  if [ "$profile" = personal ]; then
    managed_skills+=(use-railway)
    check_managed_directory \
      "$DEV_MACHINE_ROOT/config/ai/skills/use-railway" \
      "$HOME/.agents/skills/use-railway" \
      "personal Railway skill is current"
  fi
  for skill_host in .claude .codex; do
    for skill_name in "${managed_skills[@]}"; do
      skill_link="$HOME/$skill_host/skills/$skill_name"
      if [ -L "$skill_link" ] \
        && [ "$(readlink "$skill_link")" = "../../.agents/skills/$skill_name" ]; then
        pass "$skill_name skill link is current: $skill_link"
      else
        fail "$skill_name skill link is missing or incorrect: $skill_link"
      fi
    done
  done
fi

command -v git >/dev/null 2>&1 && check_version git git --version
command -v gh >/dev/null 2>&1 && check_version gh gh --version
command -v tmux >/dev/null 2>&1 && check_version tmux tmux -V
command -v mise >/dev/null 2>&1 && check_version mise mise --version
command -v go >/dev/null 2>&1 && check_version go go version
command -v node >/dev/null 2>&1 && check_version node node --version
command -v python >/dev/null 2>&1 && check_version python python --version
if [ "$profile" = work ]; then
  command -v rustc >/dev/null 2>&1 && check_version rustc rustc --version
  command -v cargo >/dev/null 2>&1 && check_version cargo cargo --version
fi
command -v age >/dev/null 2>&1 && check_version age age --version
command -v bat >/dev/null 2>&1 && check_version bat bat --version
command -v fd >/dev/null 2>&1 && check_version fd fd --version
command -v git-lfs >/dev/null 2>&1 && check_version git-lfs git lfs version
command -v sqlc >/dev/null 2>&1 && check_version sqlc sqlc version
command -v starship >/dev/null 2>&1 && check_version starship starship --version
command -v zoxide >/dev/null 2>&1 && check_version zoxide zoxide --version
if [ "$profile" = work ]; then
  command -v az >/dev/null 2>&1 \
    && check_version az az version --query '"azure-cli"' --output tsv
  command -v sqlcmd >/dev/null 2>&1 && check_version sqlcmd sqlcmd_version
  command -v sqlpackage >/dev/null 2>&1 && check_version sqlpackage sqlpackage /Version
  command -v syft >/dev/null 2>&1 && check_version syft syft version
  command -v uv >/dev/null 2>&1 && check_version uv uv --version
  command -v weasyprint >/dev/null 2>&1 \
    && check_version weasyprint weasyprint --version
  if [ "$(capture_version tesseract --version)" = 'tesseract 5.5.2' ]; then
    pass "Tesseract 5.5.2 is installed"
  else
    fail "Tesseract does not match the pinned OCR runtime"
  fi
  if timeout 10 tesseract --list-langs 2>/dev/null | grep -Fxq eng; then
    pass "Tesseract English language data is available"
  else
    fail "Tesseract English language data is missing"
  fi
  check_version pdfminer.six /usr/bin/python3 -c 'import pdfminer; print(pdfminer.__version__)'
  if ffmpeg_encoders_available; then
    pass "FFmpeg provides the required PNG, MJPEG, VPX, Vorbis and LAME encoders"
  else
    fail "FFmpeg is missing required media encoders"
  fi
elif [ "$profile" = personal ]; then
  command -v railway >/dev/null 2>&1 && check_version railway railway --version
  if [ "$skip_ai" -eq 0 ]; then
    if railway_supports_hosted_mcp; then
      pass "Railway supports the hosted MCP proxy"
    else
      fail "Railway CLI 5.44.0 or newer is required for the hosted MCP proxy"
    fi
  fi
fi
if [ "$skip_ai" -eq 0 ]; then
  command -v codex >/dev/null 2>&1 && check_version codex codex --version
  command -v claude >/dev/null 2>&1 && check_version claude claude --version
  command -v grok >/dev/null 2>&1 && check_version grok grok --version
fi

if [ -d "$HOME/code" ]; then
  pass "code directory exists: $HOME/code"
else
  fail "code directory is missing: $HOME/code"
fi

active_swap=$(swapon --show=NAME --noheadings --raw 2>/dev/null || true)
if [ -n "$active_swap" ]; then
  pass "swap is active: $(printf '%s\n' "$active_swap" | paste -sd, -)"
else
  fail "no swap is active"
fi

if oom_policy=$(systemctl --user show --property=DefaultOOMPolicy --value 2>/dev/null) \
  && [ "$oom_policy" = continue ]; then
  pass "user systemd OOM policy preserves the remaining scope processes"
else
  fail "user systemd DefaultOOMPolicy is not continue"
fi

# shellcheck disable=SC2016
shell_source_line='[ -r "$HOME/.config/dev-machine/shell.sh" ] && . "$HOME/.config/dev-machine/shell.sh"'
if grep -Fqx "$shell_source_line" "$HOME/.bashrc" 2>/dev/null; then
  pass "interactive shells load the managed environment"
else
  fail "interactive shells do not load $managed_shell_config"
fi

check_managed_file \
  "$DEV_MACHINE_ROOT/config/starship.toml" \
  "$HOME/.config/starship.toml" \
  "Starship configuration is current"

if command -v dotnet >/dev/null 2>&1; then
  case "$(command -v dotnet)" in
    "$HOME/.local/share/mise/"*) pass ".NET is managed by mise" ;;
    *) fail ".NET is not using the mise-managed SDK" ;;
  esac
  if dotnet --list-sdks 2>/dev/null | grep -Eq '^10\.'; then
    pass ".NET SDK 10 is installed"
  else
    fail ".NET SDK 10 is missing"
  fi
  if dotnet --list-sdks 2>/dev/null | grep -Eq '^8\.'; then
    fail ".NET SDK 8 is installed but is not part of the workstation policy"
  else
    pass ".NET SDK 8 is not installed"
  fi

  workload_output=$(dotnet workload list 2>/dev/null || true)
  if printf '%s\n' "$workload_output" | grep -Eq '^[[:space:]]*wasm-tools[[:space:]]'; then
    if [ "$profile" = work ]; then
      pass ".NET wasm-tools workload is installed for work"
    else
      fail ".NET wasm-tools workload is installed outside the work profile"
    fi
  elif [ "$profile" = work ]; then
    fail ".NET wasm-tools workload is missing from the work profile"
  elif [ "$profile" = personal ]; then
    pass ".NET wasm-tools workload is absent from the personal profile"
  fi

  credential_provider_version=$(
    dotnet tool list --global 2>/dev/null \
      | awk 'tolower($1) == "microsoft.artifacts.credentialprovider.nuget.tool" { print $2; exit }'
  )
  if [ -n "$credential_provider_version" ]; then
    if [ "$profile" = work ]; then
      pass "Azure Artifacts Credential Provider: $credential_provider_version"
    else
      fail "Azure Artifacts Credential Provider is installed outside the work profile"
    fi
  elif [ "$profile" = work ]; then
    fail "Azure Artifacts Credential Provider is missing from the work profile"
  else
    pass "Azure Artifacts Credential Provider is absent from the personal profile"
  fi
fi

work_mise_config="$HOME/.config/mise/conf.d/dev-machine-work.toml"
if [ "$profile" = work ]; then
  if [ -r "$work_mise_config" ]; then
    pass "work-only mise configuration is installed"
  else
    fail "work-only mise configuration is missing"
  fi
elif [ -e "$work_mise_config" ]; then
  fail "work-only mise configuration is installed outside the work profile"
else
  pass "work-only mise configuration is absent from the personal profile"
fi

personal_mise_config="$HOME/.config/mise/conf.d/dev-machine-personal.toml"
if [ "$profile" = personal ]; then
  check_managed_file "$DEV_MACHINE_ROOT/config/mise/personal.toml" "$personal_mise_config" \
    "personal-only mise configuration is current"
elif [ -e "$personal_mise_config" ]; then
  fail "personal-only mise configuration is installed outside the personal profile"
fi
if [ "$profile" = work ]; then
  if command -v railway >/dev/null 2>&1; then
    fail "Railway is installed outside the personal profile"
  fi
  for skill_host in .agents .claude .codex; do
    skill_path="$HOME/$skill_host/skills/use-railway"
    if [ -e "$skill_path" ] || [ -L "$skill_path" ]; then
      fail "Railway skill is installed outside the personal profile: $skill_path"
    fi
  done
fi

if git config --global --get-regexp '^filter\.lfs\.' >/dev/null 2>&1; then
  pass "Git LFS filters are configured"
else
  fail "Git LFS filters are not configured"
fi

database_runtime_root="$HOME/.local/share/dev-machine/docker"
installed_engines=
if [ -r "$database_runtime_root/enabled-engines" ]; then
  installed_engines=$(<"$database_runtime_root/enabled-engines")
  case "$profile:$installed_engines" in
    personal:postgres)
      pass "personal database profile enables PostgreSQL only"
      ;;
    work:"postgres mssql redis")
      pass "work database profile enables PostgreSQL, SQL Server and Redis"
      ;;
    *)
      fail "database engines do not match the $profile profile: $installed_engines"
      ;;
  esac
else
  fail "database engine profile is missing"
fi

for database_engine in postgres mssql redis; do
  compose_file="$database_runtime_root/$database_engine/compose.yaml"
  case " $installed_engines " in
    *" $database_engine "*)
      if [ -r "$compose_file" ]; then
        pass "$database_engine Compose definition is installed"
      else
        fail "$database_engine Compose definition is missing"
      fi
      ;;
    *)
      if [ -e "$compose_file" ]; then
        fail "$database_engine Compose definition is installed outside its profile"
      else
        pass "$database_engine Compose definition is absent from this profile"
      fi
      ;;
  esac
done

if [ "$profile" = personal ]; then
  for work_only_command in az cargo ffmpeg gs pandoc pdftotext qpdf redis-cli rustc sqlcmd sqlpackage syft tesseract uv weasyprint orbstack-docker-api; do
    if command -v "$work_only_command" >/dev/null 2>&1; then
      fail "$work_only_command is installed outside the work profile"
    else
      pass "$work_only_command is absent from the personal profile"
    fi
  done
  if /usr/bin/python3 -c 'import pdfminer' >/dev/null 2>&1; then
    fail "pdfminer.six is installed outside the work profile"
  fi
  for work_state in "$HOME/.config/systemd/user/dev-machine-docker-api.service" \
    "$HOME/.config/dev-machine/docker-api" "$HOME/.local/share/dev-machine/tesseract"; do
    if [ -e "$work_state" ] || [ -L "$work_state" ]; then
      fail "Work-only runtime state remains on personal: $work_state"
    fi
  done
fi

for removed_command in 7z 7zz pipx rclone; do
  if command -v "$removed_command" >/dev/null 2>&1; then
    fail "$removed_command is installed but is excluded from the workstation policy"
  else
    pass "$removed_command is absent"
  fi
done

if command -v dockerd >/dev/null 2>&1; then
  fail "dockerd is installed inside Linux; this architecture requires OrbStack host Docker"
else
  pass "no nested Docker daemon was found"
fi

if command -v mac >/dev/null 2>&1; then
  pass "OrbStack macOS command bridge is available"
  if [ "$profile" = work ]; then
    check_command orbstack-docker-api
    check_managed_file "$DEV_MACHINE_ROOT/config/systemd/dev-machine-docker-api.service" \
      "$HOME/.config/systemd/user/dev-machine-docker-api.service" "work Docker API service is current"
    if [ -d "$HOME/.config/dev-machine/docker-api" ]; then
      if orbstack-docker-api verify; then
        pass "work Docker API tunnel responds"
      else
        fail "work Docker API tunnel is not usable"
      fi
    else
      verify_warn "work Docker API tunnel is not commissioned; see docs/docker-api.md"
    fi
  fi
  if mac docker version >/dev/null 2>&1; then
    pass "OrbStack host Docker is reachable through 'mac docker'"
  else
    fail "'mac docker version' failed"
  fi
  if mac docker compose version >/dev/null 2>&1; then
    pass "OrbStack's Docker Compose plugin is reachable"
  else
    fail "'mac docker compose version' failed"
  fi
else
  verify_warn "mac bridge is absent (expected only on non-OrbStack Ubuntu)"
fi

if command -v local-dev-tls >/dev/null 2>&1; then
  if local-dev-tls verify >/dev/null 2>&1; then
    pass "local development TLS material and Ubuntu trust"
  else
    verify_warn "local development TLS is not commissioned; see docs/local-dev-tls.md"
  fi
fi

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    pass "GitHub CLI is authenticated"
  else
    verify_warn "GitHub CLI is not authenticated; run 'gh auth login'"
  fi
fi

printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
[ "$failures" -eq 0 ]
