#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
require_target_ubuntu

log "Installing the curated Ubuntu base"
sudo rm -f /etc/dev-machine-cloud-init
packages_to_remove=(
  7zip
  age
  bat
  fd-find
  fzf
  gh
  git-lfs
  p7zip
  p7zip-full
  pipx
  rclone
  ripgrep
  shellcheck
  tesseract-ocr
  zoxide
)
if [ "$DEV_INSTALL_WORK_TOOLS" -eq 0 ]; then
  packages_to_remove+=(azure-cli "${DEV_WORK_APT_PACKAGES[@]}")
fi

installed_packages_to_remove=()
for package_name in "${packages_to_remove[@]}"; do
  if dpkg-query -W -f='${db:Status-Status}' "$package_name" 2>/dev/null \
    | grep -Fqx installed; then
    installed_packages_to_remove+=("$package_name")
  fi
done
if [ "${#installed_packages_to_remove[@]}" -gt 0 ]; then
  log "Removing Ubuntu packages not owned by the selected profile"
  sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y \
    "${installed_packages_to_remove[@]}"
fi

rm -f \
  "$HOME/.local/bin/7z" \
  "$HOME/.local/bin/7zz" \
  "$HOME/.local/bin/rclone"

sudo rm -f \
  /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  /etc/apt/sources.list.d/github-cli.list
if [ "$DEV_INSTALL_WORK_TOOLS" -eq 0 ]; then
  rm -f "$HOME/.local/bin/sqlcmd"
  sudo rm -f /etc/apt/sources.list.d/azure-cli.sources
  if ! grep -RqsF '/etc/apt/keyrings/microsoft.gpg' \
    /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    sudo rm -f /etc/apt/keyrings/microsoft.gpg
  fi
fi

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  bash-completion \
  bubblewrap \
  build-essential \
  ca-certificates \
  curl \
  dnsutils \
  file \
  git \
  gnupg \
  htop \
  iproute2 \
  iputils-ping \
  jq \
  less \
  lsof \
  netcat-openbsd \
  openssh-client \
  openssl \
  pkg-config \
  procps \
  psmisc \
  python3-tomlkit \
  rsync \
  socat \
  tmux \
  traceroute \
  tree \
  unzip \
  xz-utils \
  zip

if [ -f /var/run/reboot-required ]; then
  warn "Ubuntu package upgrades require a reboot. The OrbStack lifecycle will restart this machine."
fi

mkdir -p "$DEV_CODE_DIR" "$HOME/.config/dev-machine" "$HOME/.local/bin"
info "Code directory: $DEV_CODE_DIR"
