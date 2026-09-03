#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

valid_external_volume_name() {
  case "$1" in
    ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*|.|..) return 1 ;;
    *) return 0 ;;
  esac
}

external_volume_properties_are_safe() {
  expected_mount=$1
  mount_point=$2
  internal=$3
  external_device=$4
  writable=$5

  [ "$mount_point" = "$expected_mount" ] \
    && [ "$internal" = false ] \
    && [ "$external_device" = true ] \
    && [ "$writable" = true ]
}

macos_disk_property() {
  property=$1
  expected_type=$2
  volume_path=$3

  diskutil info -plist "$volume_path" \
    | plutil -extract "$property" raw -expect "$expected_type" -o - -
}

macos_external_volume_is_valid() {
  host_volume_path=$1

  case "$(uname -s)" in
    Darwin)
      command -v diskutil >/dev/null 2>&1 || return 1
      command -v plutil >/dev/null 2>&1 || return 1
      mount_point=$(macos_disk_property MountPoint string "$host_volume_path") \
        || return 1
      internal=$(macos_disk_property Internal bool "$host_volume_path") \
        || return 1
      external_device=$(macos_disk_property RemovableMediaOrExternalDevice bool \
        "$host_volume_path") || return 1
      writable=$(macos_disk_property WritableVolume bool "$host_volume_path") \
        || return 1
      ;;
    Linux)
      command -v mac >/dev/null 2>&1 || return 1
      # shellcheck disable=SC2016
      properties=$(mac /bin/sh -c '
        path=$1
        property() {
          /usr/sbin/diskutil info -plist "$path" \
            | /usr/bin/plutil -extract "$1" raw -expect "$2" -o - -
        }
        mount_point=$(property MountPoint string) || exit 1
        internal=$(property Internal bool) || exit 1
        external_device=$(property RemovableMediaOrExternalDevice bool) || exit 1
        writable=$(property WritableVolume bool) || exit 1
        printf "%s\n%s\n%s\n%s\n" \
          "$mount_point" "$internal" "$external_device" "$writable"
      ' dev-machine-external-volume "$host_volume_path") || return 1
      mount_point=$(printf '%s\n' "$properties" | sed -n '1p')
      internal=$(printf '%s\n' "$properties" | sed -n '2p')
      external_device=$(printf '%s\n' "$properties" | sed -n '3p')
      writable=$(printf '%s\n' "$properties" | sed -n '4p')
      [ "$(printf '%s\n' "$properties" | wc -l | tr -d '[:space:]')" = 4 ] \
        || return 1
      ;;
    *) return 1 ;;
  esac

  external_volume_properties_are_safe "$host_volume_path" "$mount_point" \
    "$internal" "$external_device" "$writable"
}

main() {
  if [ -r "$ROOT/config/local/host.env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$ROOT/config/local/host.env"
  fi

  volume_name=${DEV_EXTERNAL_VOLUME:-DevArchive}
  valid_external_volume_name "$volume_name" || {
    printf 'ERROR: external volume name must be one safe path component: %s\n' \
      "$volume_name" >&2
    exit 1
  }

  host_volume_path="/Volumes/$volume_name"
  case "$(uname -s)" in
    Darwin)
      volume_path=$host_volume_path
      ;;
    Linux)
      volume_path="/mnt/mac$host_volume_path"
      ;;
    *)
      printf 'ERROR: unsupported operating system: %s\n' "$(uname -s)" >&2
      exit 1
      ;;
  esac

  if [ ! -d "$volume_path" ] \
    || ! macos_external_volume_is_valid "$host_volume_path"; then
    printf 'ERROR: expected external volume is unavailable: %s\n' "$volume_path" >&2
    printf 'Refusing to fall back to internal storage.\n' >&2
    exit 1
  fi

  printf '%s\n' "$volume_path"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
