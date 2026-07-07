# tmux-nudge — generic shell integration (zsh + bash).
#
# Nudges a pane when a foreground command finishes after running longer than
# $NUDGE_MIN_SECONDS (default 15), but only if you've switched away from it
# (see `nudge on --if-away`). Success -> "done" (green), failure -> "error" (red).
#
# Enable by sourcing this from ~/.zshrc or ~/.bashrc:
#   source /path/to/tmux-nudge/shell/nudge.sh
# or:  eval "$(/path/to/tmux-nudge/bin/nudge shell-init)"

# Threshold in seconds: $NUDGE_MIN_SECONDS env wins, else the tmux option
# @nudge-min-seconds, else 15.
if [ -z "${NUDGE_MIN_SECONDS:-}" ]; then
  NUDGE_MIN_SECONDS="$(command tmux show -gv @nudge-min-seconds 2>/dev/null || true)"
  [ -n "${NUDGE_MIN_SECONDS:-}" ] || NUDGE_MIN_SECONDS=15
fi

# Resolve bin/nudge relative to this file (works in both zsh and bash).
if [ -n "${ZSH_VERSION:-}" ]; then
  _nudge_self="${(%):-%x}"
elif [ -n "${BASH_VERSION:-}" ]; then
  _nudge_self="${BASH_SOURCE[0]}"
else
  _nudge_self=""
fi
_NUDGE_BIN="$(cd "$(dirname "${_nudge_self:-.}")/../bin" 2>/dev/null && pwd)/nudge"
unset _nudge_self
[ -x "$_NUDGE_BIN" ] || return 0 2>/dev/null || true

_nudge_preexec() { _NUDGE_START=$SECONDS; }

_nudge_precmd() {
  local exit=$?
  [ -n "${TMUX_PANE:-}" ] || { unset _NUDGE_START; return; }
  [ -n "${_NUDGE_START:-}" ] || return
  local elapsed=$(( SECONDS - _NUDGE_START ))
  unset _NUDGE_START
  [ "$elapsed" -ge "$NUDGE_MIN_SECONDS" ] || return
  local state=done
  [ "$exit" -eq 0 ] || state=error
  "$_NUDGE_BIN" on -t "$TMUX_PANE" -s "$state" --if-away >/dev/null 2>&1 &
}

if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz add-zsh-hook 2>/dev/null
  if command -v add-zsh-hook >/dev/null 2>&1; then
    add-zsh-hook preexec _nudge_preexec
    add-zsh-hook precmd  _nudge_precmd
  else
    preexec_functions+=(_nudge_preexec)
    precmd_functions+=(_nudge_precmd)
  fi
elif [ -n "${BASH_VERSION:-}" ]; then
  # preexec via DEBUG trap; precmd via PROMPT_COMMAND. Guard so preexec records
  # only for interactive commands, not for the prompt command itself.
  _nudge_bash_preexec() {
    [ -n "${COMP_LINE:-}" ] && return           # skip completion
    [ "${BASH_COMMAND}" = "${PROMPT_COMMAND:-}" ] && return
    [ -z "${_NUDGE_START:-}" ] && _NUDGE_START=$SECONDS
  }
  trap '_nudge_bash_preexec' DEBUG
  case ";${PROMPT_COMMAND:-};" in
    *";_nudge_precmd;"*) ;;
    *) PROMPT_COMMAND="_nudge_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
  esac
fi
