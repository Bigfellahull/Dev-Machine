#!/usr/bin/env bash

if [ -n "${DEV_ORB_LIB_LOADED:-}" ]; then
  return 0
fi
DEV_ORB_LIB_LOADED=1

DEV_MACHINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_ORB_DISTRO=ubuntu:resolute
DEV_ORB_ARCH=arm64
DEV_DRY_RUN=${DEV_DRY_RUN:-0}

orb_log() {
  printf '==> %s\n' "$*"
}

orb_die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

orb_usage_error() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 2
}

load_profile() {
  profile=$1
  case "$profile" in
    work|personal) ;;
    *) orb_usage_error "Profile must be 'work' or 'personal'." ;;
  esac

  # shellcheck disable=SC1090,SC1091
  . "$DEV_MACHINE_ROOT/profiles/$profile.env"

  if [ -r "$DEV_MACHINE_ROOT/config/local/host.env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$DEV_MACHINE_ROOT/config/local/host.env"
  fi

  # Distribution and architecture are repository policy, not host-local knobs.
  DEV_ORB_DISTRO=ubuntu:resolute
  DEV_ORB_ARCH=arm64
  export DEV_ORB_DISTRO DEV_ORB_ARCH

  expected_machine_name="$profile-dev"
  expected_experiment_prefix="$profile-exp"
  [ "$DEV_MACHINE_NAME" = "$expected_machine_name" ] \
    || orb_die "Host-local config must not override the primary machine name."
  [ "$DEV_EXPERIMENT_PREFIX" = "$expected_experiment_prefix" ] \
    || orb_die "Host-local config must not override the experiment prefix."

  DEV_MACHINE_CPUS=${DEV_MACHINE_CPUS:-}
  export DEV_MACHINE_PROFILE DEV_MACHINE_NAME DEV_EXPERIMENT_PREFIX
  export DEV_MACHINE_MEMORY DEV_MACHINE_DISK DEV_MACHINE_CPUS
  export DEV_EXPERIMENT_MEMORY
}

require_orbctl() {
  if [ "$DEV_DRY_RUN" -eq 0 ] && ! command -v orbctl >/dev/null 2>&1; then
    orb_die "orbctl is required on the macOS host. Install and start OrbStack."
  fi
}

print_command() {
  printf 'DRY-RUN:'
  for argument in "$@"; do
    printf ' %q' "$argument"
  done
  printf '\n'
}

run_orbctl() {
  if [ "$DEV_DRY_RUN" -eq 1 ]; then
    print_command orbctl "$@"
  else
    orbctl "$@"
  fi
}

machine_exists() {
  machine_name=$1
  if [ "$DEV_DRY_RUN" -eq 1 ]; then
    return 1
  fi
  orbctl info "$machine_name" >/dev/null 2>&1
}

validate_experiment_name() {
  experiment_name=$1
  case "$experiment_name" in
    ''|*[!a-z0-9-]*|-*|*-) orb_usage_error "Experiment names must use lowercase letters, digits and internal hyphens." ;;
  esac
  [ "${#experiment_name}" -le 40 ] || orb_usage_error "Experiment names are limited to 40 characters."
}

experiment_machine_name() {
  experiment_name=$1
  validate_experiment_name "$experiment_name"
  printf '%s-%s\n' "$DEV_EXPERIMENT_PREFIX" "$experiment_name"
}

size_to_mib() {
  size=$1
  case "$size" in
    *G) number=${size%G}; multiplier=1024 ;;
    *M) number=${size%M}; multiplier=1 ;;
    *) orb_die "Resource size must be a whole number of G or M: $size" ;;
  esac
  case "$number" in
    ''|0|0*|*[!0-9]*) orb_die "Resource size must be a canonical positive whole number: $size" ;;
  esac
  [ "${#number}" -le 9 ] || orb_die "Resource size is too large: $size"
  printf '%s\n' "$(( 10#$number * multiplier ))"
}

validate_cpu_limit() {
  cpu_limit=$1
  case "$cpu_limit" in
    ''|0|0*|*[!0-9]*) orb_die "CPU limit must be a canonical positive whole number: $cpu_limit" ;;
  esac
  [ "${#cpu_limit}" -le 9 ] || orb_die "CPU limit is too large: $cpu_limit"
}

validate_primary_resources() {
  size_to_mib "$DEV_MACHINE_MEMORY" >/dev/null
  size_to_mib "$DEV_MACHINE_DISK" >/dev/null
  if [ -n "$DEV_MACHINE_CPUS" ]; then
    validate_cpu_limit "$DEV_MACHINE_CPUS"
  fi
}

validate_create_inputs() {
  provision=$1

  validate_primary_resources
  [ -f "$DEV_MACHINE_ROOT/orb/cloud-init.yaml" ] \
    && [ ! -L "$DEV_MACHINE_ROOT/orb/cloud-init.yaml" ] \
    && [ -r "$DEV_MACHINE_ROOT/orb/cloud-init.yaml" ] \
    || orb_die "Cloud-init input is unavailable or unsafe."
  if [ "$provision" -eq 1 ]; then
    [ -f "$DEV_MACHINE_ROOT/bootstrap/bootstrap.sh" ] \
      && [ ! -L "$DEV_MACHINE_ROOT/bootstrap/bootstrap.sh" ] \
      && [ -x "$DEV_MACHINE_ROOT/bootstrap/bootstrap.sh" ] \
      || orb_die "Bootstrap entry point is unavailable or unsafe."
  fi
}

enter_machine_export_directory() {
  external_root=$1
  expected_directory="$external_root/orbstack/machine-exports"

  cd -P "$external_root" || return 1
  for directory_component in orbstack machine-exports; do
    if [ -e "$directory_component" ] || [ -L "$directory_component" ]; then
      [ -d "$directory_component" ] && [ ! -L "$directory_component" ] || return 1
    else
      mkdir "$directory_component" || return 1
    fi
    cd -P "$directory_component" || return 1
  done
  [ "$PWD" = "$expected_directory" ]
}

archive_sha256() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

write_export_manifest() {
  archive=$1
  supplied_digest=${2:-}
  manifest="$archive.manifest"
  archive_name=${archive##*/}
  if [ -n "$supplied_digest" ]; then
    digest=$supplied_digest
  else
    digest=$(archive_sha256 "$archive") || return 1
  fi

  [ ! -e "$manifest" ] && [ ! -L "$manifest" ] || return 1
  temporary_manifest=$(mktemp "${manifest}.tmp.XXXXXX") || return 1
  if ! {
    printf 'format=dev-machine-orbstack-export-v1\n'
    printf 'profile=%s\n' "$DEV_MACHINE_PROFILE"
    printf 'machine=%s\n' "$DEV_MACHINE_NAME"
    printf 'distro=%s\n' "$DEV_ORB_DISTRO"
    printf 'architecture=%s\n' "$DEV_ORB_ARCH"
    printf 'archive=%s\n' "$archive_name"
    printf 'sha256=%s\n' "$digest"
  } >"$temporary_manifest"; then
    rm -f "$temporary_manifest"
    return 1
  fi
  if ! chmod 0600 "$temporary_manifest"; then
    rm -f "$temporary_manifest"
    return 1
  fi
  if ! mv "$temporary_manifest" "$manifest"; then
    rm -f "$temporary_manifest"
    return 1
  fi
}

verify_export_manifest() {
  archive=$1
  manifest="$archive.manifest"
  archive_name=${archive##*/}
  manifest_lines=()

  [ -f "$archive" ] && [ ! -L "$archive" ] || return 1
  [ -f "$manifest" ] && [ ! -L "$manifest" ] || return 1
  while IFS= read -r manifest_line || [ -n "$manifest_line" ]; do
    manifest_lines+=("$manifest_line")
  done <"$manifest"
  [ "${#manifest_lines[@]}" -eq 7 ] || return 1
  [ "${manifest_lines[0]}" = 'format=dev-machine-orbstack-export-v1' ] || return 1
  [ "${manifest_lines[1]}" = "profile=$DEV_MACHINE_PROFILE" ] || return 1
  [ "${manifest_lines[2]}" = "machine=$DEV_MACHINE_NAME" ] || return 1
  [ "${manifest_lines[3]}" = "distro=$DEV_ORB_DISTRO" ] || return 1
  [ "${manifest_lines[4]}" = "architecture=$DEV_ORB_ARCH" ] || return 1
  [ "${manifest_lines[5]}" = "archive=$archive_name" ] || return 1
  manifest_digest=${manifest_lines[6]#sha256=}
  [ "${manifest_lines[6]}" = "sha256=$manifest_digest" ] || return 1
  case "$manifest_digest" in
    *[!0-9a-f]*|'') return 1 ;;
  esac
  [ "${#manifest_digest}" -eq 64 ] || return 1
  [ "$(archive_sha256 "$archive")" = "$manifest_digest" ]
}

confirm_delete() {
  target=$1
  confirmed=${2:-0}

  if [ "$DEV_DRY_RUN" -eq 1 ] || [ "$confirmed" -eq 1 ]; then
    return 0
  fi
  [ -t 0 ] || orb_die "Deletion requires an interactive terminal or the explicit --yes flag."

  printf "Type the exact machine name '%s' to permanently delete it: " "$target" >&2
  IFS= read -r answer
  [ "$answer" = "$target" ] || orb_die "Confirmation did not match; nothing was deleted."
}
