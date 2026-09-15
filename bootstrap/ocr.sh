#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
require_target_ubuntu

prefix="$HOME/.local/share/dev-machine/tesseract"
command_path="$HOME/.local/bin/tesseract"
[ ! -L "$prefix" ] || die "Refusing symlinked OCR installation: $prefix"
if [ -e "$prefix" ] && [ ! -f "$prefix/.dev-machine" ]; then
  die "Refusing unmanaged OCR installation: $prefix"
fi
if [ -e "$command_path" ] || [ -L "$command_path" ]; then
  [ -L "$command_path" ] && [ "$(readlink "$command_path")" = "$prefix/bin/tesseract" ] \
    || die "Refusing unmanaged tesseract command: $command_path"
fi

if [ "$DEV_INSTALL_WORK_TOOLS" -eq 0 ]; then
  rm -f "$command_path"
  [ ! -d "$prefix" ] || rm -rf "$prefix"
  exit 0
fi

# IP's OCR fixtures require this release, which is newer than Ubuntu's package.
version=5.5.2
archive_sha256=6235ea0dae45ea137f59c09320406f5888383741924d98855bd2ce0d16b54f21
installed_version=$("$prefix/bin/tesseract" --version 2>/dev/null | head -n 1 || true)
if [ "$installed_version" != "tesseract $version" ] \
  || [ "$(cat "$prefix/.dev-machine" 2>/dev/null || true)" != "$version" ]; then
  log "Building Tesseract $version for work"
  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT
  curl -fsSL "https://github.com/tesseract-ocr/tesseract/archive/refs/tags/$version.tar.gz" \
    -o "$temp_dir/tesseract.tar.gz"
  printf '%s  %s\n' "$archive_sha256" "$temp_dir/tesseract.tar.gz" | sha256sum --check --status
  tar -xzf "$temp_dir/tesseract.tar.gz" -C "$temp_dir"
  mkdir -p "$prefix"
  touch "$prefix/.dev-machine"
  cmake -S "$temp_dir/tesseract-$version" -B "$temp_dir/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DTESSDATA_PREFIX="$prefix/share" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TRAINING_TOOLS=OFF -DBUILD_TESTS=OFF \
    -DGRAPHICS_DISABLED=ON -DENABLE_NATIVE=OFF -DDISABLE_CURL=ON -DDISABLE_ARCHIVE=ON
  cmake --build "$temp_dir/build" --parallel 2
  cmake --install "$temp_dir/build"
fi

mkdir -p "$prefix/share/tessdata" "$HOME/.local/bin"
for language in eng osd; do
  language_data="/usr/share/tesseract-ocr/5/tessdata/$language.traineddata"
  [ -r "$language_data" ] || die "Missing OCR language data: $language_data"
  ln -sfn "$language_data" "$prefix/share/tessdata/$language.traineddata"
done
ln -sfn "$prefix/bin/tesseract" "$command_path"
"$command_path" --version
timeout 10 "$command_path" --list-langs | grep -Fx eng >/dev/null
printf '%s\n' "$version" >"$prefix/.dev-machine"
