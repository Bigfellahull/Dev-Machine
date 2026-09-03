#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
require_target_ubuntu

install_native_cli() {
  cli_name=$1
  installer_url=$2

  if command -v "$cli_name" >/dev/null 2>&1 \
    || [ -x "$HOME/.local/bin/$cli_name" ] \
    || [ -x "$HOME/.$cli_name/bin/$cli_name" ]; then
    info "$cli_name is already installed"
    return 0
  fi

  log "Installing $cli_name from its official native installer"
  temp_installer=$(mktemp)
  curl -fsSL "$installer_url" -o "$temp_installer"
  bash "$temp_installer"
  rm -f "$temp_installer"
}

install_managed_skill() {
  source_directory=$1
  target_directory=$2

  [ -d "$source_directory" ] || die "Managed skill source is missing: $source_directory"
  [ ! -L "$target_directory" ] || die "Refusing to replace symlinked skill directory: $target_directory"
  if [ -e "$target_directory" ] && [ ! -d "$target_directory" ]; then
    die "Managed skill target is not a directory: $target_directory"
  fi
  mkdir -p "$target_directory"
  rsync -a --delete "$source_directory/" "$target_directory/"
}

install_skill_symlink() {
  link_target=$1
  link_path=$2

  mkdir -p "$(dirname "$link_path")"
  if [ -L "$link_path" ]; then
    [ "$(readlink "$link_path")" = "$link_target" ] \
      || die "Refusing to replace unexpected skill symlink: $link_path"
    return 0
  fi
  [ ! -e "$link_path" ] || die "Refusing to replace existing skill path: $link_path"
  ln -s "$link_target" "$link_path"
}

# Authentication and provider credentials are intentionally not handled here.
install_native_cli codex https://chatgpt.com/codex/install.sh
install_native_cli claude https://claude.ai/install.sh
install_native_cli grok https://x.ai/cli/install.sh

log "Installing safe AI CLI defaults"
install_user_file_if_missing \
  "$DEV_MACHINE_ROOT/config/ai/codex.toml" \
  "$HOME/.codex/config.toml" \
  0600
install_user_file_if_missing \
  "$DEV_MACHINE_ROOT/config/ai/claude.json" \
  "$HOME/.claude/settings.json" \
  0600
install_user_file_if_missing \
  "$DEV_MACHINE_ROOT/config/ai/grok.toml" \
  "$HOME/.grok/config.toml" \
  0600
install_user_file_if_missing \
  "$DEV_MACHINE_ROOT/config/ai/grok-sandbox.toml" \
  "$HOME/.grok/sandbox.toml" \
  0600

log "Installing managed AI instructions and skills"
install_user_file \
  "$DEV_MACHINE_ROOT/config/ai/AGENTS.md" \
  "$HOME/.codex/AGENTS.md"
install_user_file \
  "$DEV_MACHINE_ROOT/config/ai/AGENTS.md" \
  "$HOME/.grok/AGENTS.md"
install_user_file \
  "$DEV_MACHINE_ROOT/config/ai/CLAUDE.md" \
  "$HOME/.claude/CLAUDE.md"
install_managed_skill \
  "$DEV_MACHINE_ROOT/config/ai/skills/codebase-sweep" \
  "$HOME/.agents/skills/codebase-sweep"
install_managed_skill \
  "$DEV_MACHINE_ROOT/config/ai/skills/collab" \
  "$HOME/.codex/skills/collab"
install_skill_symlink \
  '../../.agents/skills/codebase-sweep' \
  "$HOME/.claude/skills/codebase-sweep"
