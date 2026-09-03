#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
require_target_ubuntu

log "Installing work-only utilities from Ubuntu"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  "${DEV_WORK_APT_PACKAGES[@]}"

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

log "Installing Azure CLI from Microsoft's supported apt repository"
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o "$temp_dir/microsoft.asc"
gpg --batch --yes --dearmor --output "$temp_dir/microsoft.gpg" "$temp_dir/microsoft.asc"
sudo install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
sudo install -m 0644 "$temp_dir/microsoft.gpg" /etc/apt/keyrings/microsoft.gpg
cat >"$temp_dir/azure-cli.sources" <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: resolute
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/microsoft.gpg
EOF
sudo install -m 0644 "$temp_dir/azure-cli.sources" /etc/apt/sources.list.d/azure-cli.sources
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y azure-cli

log "Installing the latest official sqlcmd ARM64 release"
sqlcmd_metadata="$temp_dir/sqlcmd-release.json"
sqlcmd_archive="$temp_dir/sqlcmd-linux-arm64.tar.bz2"
curl -fsSL https://api.github.com/repos/microsoft/go-sqlcmd/releases/latest -o "$sqlcmd_metadata"
sqlcmd_url=$(jq -er '.assets[] | select(.name == "sqlcmd-linux-arm64.tar.bz2") | .browser_download_url' "$sqlcmd_metadata")
sqlcmd_sha256=$(jq -er '.assets[] | select(.name == "sqlcmd-linux-arm64.tar.bz2") | .digest | sub("^sha256:"; "")' "$sqlcmd_metadata")
curl -fsSL "$sqlcmd_url" -o "$sqlcmd_archive"
printf '%s  %s\n' "$sqlcmd_sha256" "$sqlcmd_archive" | sha256sum --check --status
tar -xjf "$sqlcmd_archive" -C "$temp_dir"
install -m 0755 "$temp_dir/sqlcmd" "$HOME/.local/bin/sqlcmd"
