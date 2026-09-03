#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
require_target_ubuntu

if command -v add-apt-repository >/dev/null 2>&1 \
  && grep -Rqs 'dotnet/backports' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  log "Removing the obsolete .NET backports PPA"
  sudo add-apt-repository --remove -y ppa:dotnet/backports
fi

ubuntu_dotnet_packages=()
while IFS=$'\t' read -r package_name package_status; do
  [ "$package_status" = installed ] || continue
  case "$package_name" in
    aspnetcore-*|dotnet-*|netstandard-targeting-pack-*)
      ubuntu_dotnet_packages+=("$package_name")
      ;;
  esac
done < <(dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\n' 2>/dev/null)

if [ "${#ubuntu_dotnet_packages[@]}" -gt 0 ]; then
  log "Removing Ubuntu-packaged .NET SDK and runtime files"
  sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y "${ubuntu_dotnet_packages[@]}"
fi

log "Installing native dependencies for Microsoft's .NET binaries"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  libc6 \
  libgcc-s1 \
  libgssapi-krb5-2 \
  libicu78 \
  liblttng-ust1t64 \
  libssl3t64 \
  libstdc++6 \
  tzdata \
  zlib1g
