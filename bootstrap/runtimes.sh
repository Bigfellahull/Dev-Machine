#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
require_target_ubuntu

: "${DEV_INSTALL_DOTNET_WASM_TOOLS:=0}"
: "${DEV_INSTALL_WORK_TOOLS:=0}"

log "Installing the latest mise release"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
curl -fsSL https://mise.run -o "$temp_dir/install-mise.sh"
MISE_INSTALL_PATH="$HOME/.local/bin/mise" \
  sh "$temp_dir/install-mise.sh"
mise="$HOME/.local/bin/mise"

install_user_file \
  "$DEV_MACHINE_ROOT/config/mise/config.toml" \
  "$HOME/.config/mise/config.toml"

work_config="$HOME/.config/mise/conf.d/dev-machine-work.toml"
if [ "$DEV_INSTALL_WORK_TOOLS" -eq 1 ]; then
  install_user_file "$DEV_MACHINE_ROOT/config/mise/work.toml" "$work_config"
else
  rm -f "$work_config"
  log "Removing work-only mise tools from the personal profile"
  "$mise" uninstall --all "pipx:weasyprint" rust syft uv
fi

rm -f "$HOME/.local/bin/sqlc" "$HOME/.local/bin/syft"

if [ "$DEV_INSTALL_WORK_TOOLS" -eq 1 ]; then
  log "Installing uv before its work-only Python CLI"
  "$mise" install --yes uv --minimum-release-age 0s
fi

log "Installing and updating mise-managed development tools"
eval "$("$mise" activate bash)"
"$mise" install --yes --minimum-release-age 0s
"$mise" upgrade --yes --prune --minimum-release-age 0s

credential_provider_package=Microsoft.Artifacts.CredentialProvider.NuGet.Tool
credential_provider_version=$(
  "$mise" exec -- dotnet tool list --global \
    | awk 'tolower($1) == "microsoft.artifacts.credentialprovider.nuget.tool" { print $2; exit }'
)
if [ "$DEV_INSTALL_WORK_TOOLS" -eq 1 ]; then
  if [ -n "$credential_provider_version" ]; then
    log "Updating the Azure Artifacts Credential Provider"
    "$mise" exec -- dotnet tool update --global "$credential_provider_package" \
      --source https://api.nuget.org/v3/index.json
  else
    log "Installing the latest Azure Artifacts Credential Provider"
    "$mise" exec -- dotnet tool install --global "$credential_provider_package" \
      --source https://api.nuget.org/v3/index.json
  fi
elif [ -n "$credential_provider_version" ]; then
  log "Removing the work-only Azure Artifacts Credential Provider"
  "$mise" exec -- dotnet tool uninstall --global "$credential_provider_package"
fi

if [ "$DEV_INSTALL_DOTNET_WASM_TOOLS" -eq 1 ]; then
  log "Installing the .NET wasm-tools workload for the work profile"
  "$mise" exec -- dotnet workload install wasm-tools
elif "$mise" exec -- dotnet workload list 2>/dev/null \
  | grep -Eq '^[[:space:]]*wasm-tools[[:space:]]'; then
  log "Removing the work-only .NET wasm-tools workload"
  "$mise" exec -- dotnet workload uninstall wasm-tools
fi
