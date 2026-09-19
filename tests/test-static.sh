#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

while IFS= read -r script; do
  bash -n "$script"
done < <(rg --files bootstrap orb scripts tests bin | while IFS= read -r file; do
  if head -n 1 "$file" | grep -q 'bash'; then
    printf '%s\n' "$file"
  fi
done)
printf 'Bash syntax: ok\n'

if command -v shellcheck >/dev/null 2>&1; then
  # The linter sees library files because every script is passed together.
  shell_scripts=()
  while IFS= read -r script; do
    shell_scripts+=("$script")
  done < <(rg --files bootstrap orb scripts tests bin | while IFS= read -r file; do
    if head -n 1 "$file" | grep -q 'bash'; then
      printf '%s\n' "$file"
    fi
  done)
  shellcheck "${shell_scripts[@]}" config/shell/dev-machine.sh
  printf 'ShellCheck: ok\n'
else
  printf 'ShellCheck: skipped (not installed)\n'
fi

if docker compose version >/dev/null 2>&1; then
  compose_command=(docker compose)
elif [ -x /Applications/OrbStack.app/Contents/MacOS/xbin/docker-compose ]; then
  compose_command=(/Applications/OrbStack.app/Contents/MacOS/xbin/docker-compose)
else
  compose_command=()
fi

if [ "${#compose_command[@]}" -gt 0 ]; then
  for engine in postgres mssql redis; do
    "${compose_command[@]}" \
      --env-file docker/images.env \
      --env-file docker/db.env.example \
      -f "docker/$engine/compose.yaml" config --quiet
  done
  printf 'Compose definitions: ok\n'
else
  printf 'Compose definitions: skipped (Compose parser unavailable)\n'
fi

if git grep -nE '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(proj-)?[A-Za-z0-9_-]{20,}|xai-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})' -- . ':!tests/test-static.sh'; then
  printf 'Potential committed secret detected.\n' >&2
  exit 1
fi

if git grep -nE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' -- . ':!tests/test-static.sh'; then
  printf 'A private key is committed.\n' >&2
  exit 1
fi

if git ls-files | grep -Eq '(^|/)(rootCA-key\.pem|localhost-key\.pem|localhost\.pfx(-password)?)$'; then
  printf 'Generated TLS private material is tracked.\n' >&2
  exit 1
fi

if git ls-files | grep -Eq '(^|/)(\.env|id_(rsa|ed25519))$'; then
  printf 'A secret-shaped file is tracked.\n' >&2
  exit 1
fi

if git grep -nE '/Users/[[:alnum:]_.-]+/' -- . ':!tests/test-static.sh'; then
  printf 'A local macOS home path is tracked.\n' >&2
  exit 1
fi

git diff --check
printf 'Static repository checks: ok\n'

grep -Fq 'sudo -n true' bootstrap/bootstrap.sh
grep -Fq 'sudo mac link docker' bootstrap/docker-bridge.sh
bootstrap/verify.sh --help >/dev/null
grep -Fq 'AI CLI checks were intentionally skipped' bootstrap/verify.sh
grep -Fq ". \"\$managed_shell_config\"" bootstrap/verify.sh
grep -Fq 'interactive shells load the managed environment' bootstrap/verify.sh
[ "$(sed -n '1p' config/mise/config.toml)" = 'min_version = "2026.9.0"' ]
if sed -n '/^\[settings\]/,$p' config/mise/config.toml | grep -Eq '^min_version[[:space:]]*='; then
  printf 'mise min_version must be a top-level key.\n' >&2
  exit 1
fi

grep -Fq 'package_upgrade: true' orb/cloud-init.yaml
grep -Fq 'package_reboot_if_required: false' orb/cloud-init.yaml
if grep -Fq 'dev-machine-cloud-init' orb/cloud-init.yaml; then
  printf 'The unused cloud-init marker must not be written.\n' >&2
  exit 1
fi
grep -Fq 'sudo rm -f /etc/dev-machine-cloud-init' bootstrap/base.sh
grep -Fq "\"\$SCRIPT_DIR/memory.sh\"" bootstrap/bootstrap.sh
grep -Fq 'swap_size=8G' bootstrap/memory.sh
grep -Fq 'Active swap already exists; leaving it unchanged.' bootstrap/memory.sh
grep -Fq 'DefaultOOMPolicy=continue' config/systemd/user.conf.d/90-dev-machine-oom.conf
grep -Fq 'user systemd DefaultOOMPolicy is not continue' bootstrap/verify.sh

grep -Fq 'build-essential' bootstrap/base.sh
grep -Fq 'bubblewrap' bootstrap/base.sh
grep -Fq 'socat' bootstrap/base.sh
grep -Fq 'openssl' bootstrap/base.sh
grep -Fq 'bin/local-dev-tls' bootstrap/shell.sh
grep -Fq 'local development TLS is not commissioned' bootstrap/verify.sh
for redundant_package in make software-properties-common wget; do
  if grep -Eq "^[[:space:]]+${redundant_package}[[:space:]\\]*$" bootstrap/base.sh; then
    printf 'Redundant base package is explicitly managed: %s\n' "$redundant_package" >&2
    exit 1
  fi
done

jq -e '
  .model == "claude-fable-5-1"
  and .effortLevel == "high"
  and .theme == "auto"
  and .permissions.defaultMode == "auto"
  and .sandbox.enabled == true
  and .sandbox.autoAllowBashIfSandboxed == false
  and .sandbox.allowUnsandboxedCommands == false
  and .sandbox.failIfUnavailable == true
  and .env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB == "1"
' config/ai/claude.json >/dev/null
grep -Fq 'model = "gpt-6-astra"' config/ai/codex.toml
grep -Fq 'model_reasoning_effort = "high"' config/ai/codex.toml
grep -Fq 'goals = true' config/ai/codex.toml
grep -Fq 'approval_policy = "on-request"' config/ai/codex.toml
grep -Fq 'approvals_reviewer = "auto_review"' config/ai/codex.toml
grep -Fq 'sandbox_mode = "workspace-write"' config/ai/codex.toml
grep -Fq '[shell_environment_policy]' config/ai/codex.toml
grep -Fq 'ignore_default_excludes = false' config/ai/codex.toml
grep -Fq '[mcp_servers.openaiDeveloperDocs]' config/ai/codex.toml
grep -Fq 'url = "https://developers.openai.com/mcp"' config/ai/codex.toml
grep -Fq 'permission_mode = "auto"' config/ai/grok.toml
grep -Fq 'max_thoughts_width = 120' config/ai/grok.toml
grep -Fq 'screen_mode = "minimal"' config/ai/grok.toml
grep -Fq 'profile = "safe-workspace"' config/ai/grok.toml
grep -Fq 'auto_allow_bash = false' config/ai/grok.toml
grep -Fq 'ignore_default_excludes = false' config/ai/grok.toml
grep -Fq '[profiles.safe-workspace]' config/ai/grok-sandbox.toml
grep -Fq 'extends = "workspace"' config/ai/grok-sandbox.toml
grep -Fq 'ai-config.py" apply' bootstrap/ai-tools.sh
grep -Fq 'config/ai/skills/codebase-sweep' bootstrap/ai-tools.sh
grep -Fq 'config/ai/skills/collab' bootstrap/ai-tools.sh
grep -Fq "'../../.agents/skills/codebase-sweep'" bootstrap/ai-tools.sh
grep -Fq '@~/.codex/AGENTS.md' config/ai/CLAUDE.md
grep -Fq 'Pasteable Output' config/ai/AGENTS.md
[ -f config/ai/skills/codebase-sweep/SKILL.md ]
[ -f config/ai/skills/collab/SKILL.md ]
[ -x config/ai/skills/collab/scripts/partner_turn.py ]
if find config/ai/skills -name .DS_Store -print -quit | grep -q .; then
  printf 'Finder metadata must not be copied with managed skills.\n' >&2
  exit 1
fi
if find config/ai/skills \( -type d -name __pycache__ -o -type f -name '*.pyc' \) \
  -print -quit | grep -q .; then
  printf 'Generated Python artifacts must not be copied with managed skills.\n' >&2
  exit 1
fi
if find config/ai/skills -mindepth 1 -maxdepth 1 -type d ! -name codebase-sweep ! -name collab ! -name use-railway \
  -print -quit | grep -q .; then
  printf 'An unapproved managed AI skill is present.\n' >&2
  exit 1
fi

grep -Eq '^dotnet[[:space:]]*=[[:space:]]*"10"$' config/mise/config.toml
grep -Eq '^starship[[:space:]]*=[[:space:]]*"latest"$' config/mise/config.toml
grep -Fq 'fzf --bash' config/shell/dev-machine.sh
grep -Fq 'zoxide init bash' config/shell/dev-machine.sh
grep -Fq 'starship init bash' config/shell/dev-machine.sh
grep -Fq "alias finish-dev='tmux kill-session'" config/shell/dev-machine.sh
grep -Fq 'config/starship.toml' bootstrap/shell.sh
grep -Fq 'allow-passthrough on' config/tmux/tmux.conf
grep -Fq 'extended-keys on' config/tmux/tmux.conf
grep -Fq "terminal-features 'xterm*:extkeys'" config/tmux/tmux.conf
grep -Fq "terminal-features ',xterm-ghostty:RGB'" config/tmux/tmux.conf
grep -Fq "status-style 'bg=default,fg=colour8'" config/tmux/tmux.conf
grep -Fq 'window-status-current-format' config/tmux/tmux.conf
grep -Fq 'pane-active-border-style' config/tmux/tmux.conf
grep -Fq 'clock-mode-colour colour4' config/tmux/tmux.conf
if rg -q 'DOTNET_SDK.*8|DOTNET_SDK_PACKAGE|DOTNET_CHANNEL' config bootstrap \
  || grep -Eq 'add-apt-repository[[:space:]]+-y[[:space:]]+ppa:dotnet/backports' bootstrap/dotnet.sh; then
  printf 'The active configuration must not install .NET 8 or add its PPA.\n' >&2
  exit 1
fi
grep -Fq 'DEV_INSTALL_DOTNET_WASM_TOOLS=0' profiles/common.env
grep -Fq 'DEV_INSTALL_DOTNET_WASM_TOOLS=1' profiles/work.env
grep -Fq 'DEV_INSTALL_WORK_TOOLS=0' profiles/common.env
grep -Fq 'DEV_INSTALL_WORK_TOOLS=1' profiles/work.env
grep -Fq 'DEV_MACHINE_DB_ENGINES="postgres"' profiles/common.env
grep -Fq 'DEV_MACHINE_DB_ENGINES="postgres mssql redis"' profiles/work.env
grep -Fq 'workload install wasm-tools' bootstrap/runtimes.sh
grep -Fq 'workload uninstall wasm-tools' bootstrap/runtimes.sh
grep -Fq "dotnet tool install --global \"\$credential_provider_package\"" bootstrap/runtimes.sh
grep -Fq "dotnet tool update --global \"\$credential_provider_package\"" bootstrap/runtimes.sh
grep -Fq "dotnet tool uninstall --global \"\$credential_provider_package\"" bootstrap/runtimes.sh
grep -Fq 'Azure Artifacts Credential Provider is missing from the work profile' bootstrap/verify.sh
grep -Fq 'Azure Artifacts Credential Provider is absent from the personal profile' bootstrap/verify.sh
grep -Fq "*\":\$HOME/.dotnet/tools:\"*" config/shell/dev-machine.sh
if sed -n "/^credential_provider_package=/,/^if \\[ \"\$DEV_INSTALL_DOTNET_WASM_TOOLS\"/p" \
  bootstrap/runtimes.sh | grep -Fq -- '--version'; then
  printf 'The Azure Artifacts Credential Provider must track the latest stable release.\n' >&2
  exit 1
fi
grep -Fq 'libicu78' bootstrap/dotnet.sh
if grep -Fq 'dotnet-install.sh' bootstrap/dotnet.sh; then
  printf '.NET installation must be delegated to mise.\n' >&2
  exit 1
fi

for runtime in age bat fd fzf git-lfs github-cli go node python ripgrep shellcheck sqlc starship zoxide; do
  grep -Eq "^${runtime}[[:space:]]*=[[:space:]]*\"latest\"$" config/mise/config.toml
done
grep -Eq '^rust[[:space:]]*=[[:space:]]*\{ version = "latest", profile = "default" \}$' config/mise/work.toml
for work_tool in syft uv; do
  grep -Eq "^${work_tool}[[:space:]]*=[[:space:]]*\"latest\"$" config/mise/work.toml
done
grep -Fq '"pipx:weasyprint" = "latest"' config/mise/work.toml
if rg -q '^MISE_VERSION=' config bootstrap; then
  printf 'mise must not be pinned by the bootstrap.\n' >&2
  exit 1
fi
if grep -Fq 'MISE_INSTALL_SKIP_IF_EXISTS' bootstrap/runtimes.sh; then
  printf 'The latest mise installer must be allowed to update an existing binary.\n' >&2
  exit 1
fi
grep -Fq 'mise" install --yes --minimum-release-age 0s' bootstrap/runtimes.sh
grep -Fq 'mise" upgrade --yes --prune --minimum-release-age 0s' bootstrap/runtimes.sh
grep -Fq 'config/mise/work.toml' bootstrap/runtimes.sh
grep -Fq "rm -f \"\$work_config\"" bootstrap/runtimes.sh
grep -Fq 'uninstall --all "pipx:weasyprint" rust syft uv' bootstrap/runtimes.sh

for excluded_script in bootstrap/github.sh bootstrap/rust.sh; do
  if [ -e "$excluded_script" ]; then
    printf 'Excluded standalone installer exists: %s\n' "$excluded_script" >&2
    exit 1
  fi
done
if rg -q 'go install github.com/sqlc-dev|https://get.anchore.io/syft|cli.github.com/packages' bootstrap; then
  printf 'A mise-managed CLI has a standalone installer.\n' >&2
  exit 1
fi
if rg -q 'bufbuild/buf|protoc-gen-go|caddy' bootstrap; then
  printf 'Project-specific dependencies must not be installed globally.\n' >&2
  exit 1
fi
if rg -q 'mkcert' bootstrap config bin; then
  printf 'mkcert must remain on the Mac host, not inside Ubuntu.\n' >&2
  exit 1
fi
grep -Fq 'api.github.com/repos/microsoft/go-sqlcmd/releases/latest' bootstrap/work-tools.sh
grep -Fq 'sha256sum --check --status' bootstrap/work-tools.sh
grep -Fq 'https://packages.microsoft.com/repos/azure-cli/' bootstrap/work-tools.sh
for work_package in bzip2 ffmpeg ghostscript libharfbuzz-subset0 libharfbuzz0b libpango-1.0-0 libpangoft2-1.0-0 pandoc poppler-utils qpdf redis-tools; do
  grep -Fq "$work_package" bootstrap/lib.sh
  if grep -Fq "$work_package" bootstrap/workstation-tools.sh; then
    printf 'Work-only package is installed by the common profile: %s\n' "$work_package" >&2
    exit 1
  fi
done
if grep -Eq '^[[:space:]]+pipx[[:space:]\\]*$' bootstrap/work-tools.sh; then
  printf 'Standalone pipx must not be installed with apt.\n' >&2
  exit 1
fi
for mise_package in age bat fd-find fzf gh git-lfs ripgrep shellcheck zoxide; do
  if sed -n '/apt-get install -y \\/,/^$/p' \
    bootstrap/base.sh bootstrap/workstation-tools.sh bootstrap/work-tools.sh \
    | grep -Eq "^[[:space:]]+${mise_package}[[:space:]\\]*$"; then
    printf 'mise-managed command is installed with apt: %s\n' "$mise_package" >&2
    exit 1
  fi
done
grep -Fq -- '--delete-excluded' bootstrap/shell.sh
grep -Fq 'enabled-engines' bootstrap/shell.sh
grep -Fq 'for removed_command in 7z 7zz pipx rclone' bootstrap/verify.sh
for excluded_package in 7zip p7zip p7zip-full rclone; do
  grep -Eq "^[[:space:]]+${excluded_package}[[:space:]\)]*$" bootstrap/base.sh
done
for excluded_binary in 7z 7zz rclone; do
  grep -Fq "\$HOME/.local/bin/${excluded_binary}" bootstrap/base.sh
done
# shellcheck disable=SC2016
grep -Fq 'packages_to_remove+=(azure-cli "${DEV_WORK_APT_PACKAGES[@]}")' bootstrap/base.sh
grep -Fq "rm -f \"\$HOME/.local/bin/sqlcmd\"" bootstrap/base.sh
grep -Fq 'sudo rm -f /etc/apt/sources.list.d/azure-cli.sources' bootstrap/base.sh
if rg -qi 'awscli|aws cli|colima' bootstrap config; then
  printf 'An excluded workstation tool is installed in Linux.\n' >&2
  exit 1
fi
if rg -qi 'rclone|7zip|p7zip' bootstrap config \
  --glob '!bootstrap/base.sh' \
  --glob '!bootstrap/verify.sh'; then
  printf 'An excluded workstation tool appears outside convergence cleanup.\n' >&2
  exit 1
fi

grep -Fq 'followTags = true' config/git/dev-machine.inc
grep -Fq 'rebase = true' config/git/dev-machine.inc
grep -Fq 'mise" exec -- git lfs install --skip-repo' bootstrap/shell.sh
printf 'Bootstrap integration guards: ok\n'
