#!/usr/bin/env bash

if [ -n "${DEV_MACHINE_LIB_LOADED:-}" ]; then
  return 0
fi
DEV_MACHINE_LIB_LOADED=1

DEV_MACHINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_MACHINE_ROOT

# shellcheck disable=SC2034
DEV_WORK_APT_PACKAGES=(
  binutils-mingw-w64-x86-64
  bzip2
  cmake
  ffmpeg
  ghostscript
  libharfbuzz-subset0
  libharfbuzz0b
  libpango-1.0-0
  libpangoft2-1.0-0
  libleptonica-dev
  libtiff-dev
  libunwind8
  pandoc
  poppler-utils
  python3-pdfminer
  qpdf
  redis-tools
  tesseract-ocr-eng
  tesseract-ocr-osd
)

log() {
  printf '\n==> %s\n' "$*"
}

info() {
  printf '    %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_target_ubuntu() {
  [ "$(uname -s)" = Linux ] || die "Bootstrap must run inside Linux, not $(uname -s)."
  [ -r /etc/os-release ] || die "Cannot identify the Linux distribution."

  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${ID:-}" = ubuntu ] || die "Ubuntu is required; detected ${ID:-unknown}."

  if [ "${VERSION_ID:-}" != 26.04 ]; then
    die "Ubuntu 26.04 is required by this revision; detected ${VERSION_ID:-unknown}."
  fi

  case "$(uname -m)" in
    aarch64|arm64) ;;
    *) die "ARM64 is required; detected $(uname -m)." ;;
  esac
}

install_user_file() {
  source_file=$1
  target_file=$2
  mode=${3:-0644}

  mkdir -p "$(dirname "$target_file")"
  if [ -f "$target_file" ] && cmp -s "$source_file" "$target_file"; then
    return 0
  fi
  install -m "$mode" "$source_file" "$target_file"
}

# Vendor config may accumulate private runtime choices that bootstrap must preserve.
install_user_file_if_missing() {
  source_file=$1
  target_file=$2
  mode=${3:-0644}

  mkdir -p "$(dirname "$target_file")"
  if [ -e "$target_file" ] || [ -L "$target_file" ]; then
    [ -f "$target_file" ] || die "Expected a file at $target_file"
    return 0
  fi
  install -m "$mode" "$source_file" "$target_file"
}

ensure_line() {
  target_file=$1
  line=$2

  mkdir -p "$(dirname "$target_file")"
  touch "$target_file"
  if ! grep -Fqx "$line" "$target_file"; then
    printf '%s\n' "$line" >>"$target_file"
  fi
}
