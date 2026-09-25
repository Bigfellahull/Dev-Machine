# shellcheck shell=sh
# Managed by dev-machine. This file may also be read by POSIX login shells.
if [ -n "${BASH_VERSION:-}" ] && [ -z "${DEV_MACHINE_SHELL_LOADED:-}" ]; then
  case $- in
    *i*)
      if [ -r "$HOME/.config/dev-machine/shell.sh" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.config/dev-machine/shell.sh"
      fi
      ;;
  esac
fi
