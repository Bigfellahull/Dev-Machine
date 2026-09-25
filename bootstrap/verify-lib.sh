#!/usr/bin/env bash

# Check login startup independently of the verifier's repaired environment.
bash_login_loads_environment() (
  cd "$HOME" || return 1
  # shellcheck disable=SC2016
  env -u BASH_ENV -u ENV DEV_MACHINE_SHELL_LOADED= PATH=/usr/bin:/bin \
    /bin/bash -lic 'test "${DEV_MACHINE_SHELL_LOADED:-}" = 1' </dev/null
)

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

# Older releases route the same MCP command to a different server implementation.
railway_supports_hosted_mcp() {
  local version
  version=$(railway --version) || return 1
  printf '%s\n' "$version" | awk '
    match($0, /[0-9]+\.[0-9]+\.[0-9]+/) {
      split(substr($0, RSTART, RLENGTH), parts, ".")
      found = 1
      supported = (parts[1] > 5 || (parts[1] == 5 && parts[2] >= 44))
      exit
    }
    END { exit !(found && supported) }
  '
}

# Check the concrete encoders used by the work media pipeline.
ffmpeg_encoders_available() {
  local encoders encoder
  encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null) || return 1
  for encoder in png mjpeg libvpx libvpx-vp9 libvorbis libmp3lame; do
    printf '%s\n' "$encoders" | awk '{print $2}' | grep -Fxq "$encoder" || return 1
  done
}
