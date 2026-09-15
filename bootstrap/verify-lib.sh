#!/usr/bin/env bash

capture_version() {
  version_output=$("$@" 2>&1) || return 1
  version_output=$(printf '%s\n' "$version_output" | head -n 1)
  [ -n "${version_output//[[:space:]]/}" ] || return 1
  printf '%s\n' "$version_output"
}

sqlcmd_version() {
  sqlcmd_output=$(sqlcmd --version) || return 1
  parsed_version=$(printf '%s\n' "$sqlcmd_output" \
    | awk '/^Version:/ { print $2; exit }')
  [ -n "$parsed_version" ] || return 1
  printf '%s\n' "$parsed_version"
}

# Check the concrete encoders used by the work media pipeline.
ffmpeg_encoders_available() {
  local encoders encoder
  encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null) || return 1
  for encoder in png mjpeg libvpx libvpx-vp9 libvorbis libmp3lame; do
    printf '%s\n' "$encoders" | awk '{print $2}' | grep -Fxq "$encoder" || return 1
  done
}
