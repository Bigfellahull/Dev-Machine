# shellcheck shell=bash
# Managed by dev-machine. Put private or machine-local settings elsewhere.
alias finish-dev='tmux kill-session'

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.dotnet/tools:"*) ;;
  *) export PATH="$HOME/.dotnet/tools:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.grok/bin:"*) ;;
  *) export PATH="$HOME/.grok/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.codex/bin:"*) ;;
  *) export PATH="$HOME/.codex/bin:$PATH" ;;
esac

if [ -x "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate bash)"
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
