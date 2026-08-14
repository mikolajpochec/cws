#!/usr/bin/env bash
# cws bash entrypoint. source this from ~/.bashrc with CWS_HOME set to this
# repo's checkout path (install.sh wires this up for you):
#
#   export CWS_HOME="$HOME/dev/cws"
#   [ -f "$CWS_HOME/shell/cws.bash" ] && source "$CWS_HOME/shell/cws.bash"
#
# private data (which workspaces exist, their config dirs) lives outside this
# repo in $CWS_ROOT (default ~/.config/claude-workspaces) - nothing here.
#
# bash has no chpwd hook, so PROMPT_COMMAND re-checks $PWD each prompt draw -
# cheap (a registry read + glob matches), and skipped entirely unless $PWD
# actually changed since the last prompt.

if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "cws.bash: needs bash 4+ (associative arrays) - this shell is ${BASH_VERSION:-unknown}." >&2
  echo "  macOS ships bash 3.2; install a newer one, e.g.: brew install bash" >&2
  return 1 2>/dev/null || exit 1
fi

: "${CWS_HOME:?cws.bash: set CWS_HOME to this repo path before sourcing}"
: "${CWS_ROOT:=$HOME/.config/claude-workspaces}"
export CWS_HOME CWS_ROOT
CWS_REG="$CWS_ROOT/workspaces"

source "$CWS_HOME/lib/registry.sh"
source "$CWS_HOME/lib/colors.sh"
source "$CWS_HOME/lib/theme-gen.sh"
source "$CWS_HOME/lib/commands.sh"
source "$CWS_HOME/lib/prompt.sh"

_CWS_LAST_PWD=""
_cws_precmd() {
  if [[ "$PWD" != "$_CWS_LAST_PWD" ]]; then
    _CWS_LAST_PWD="$PWD"
    _cws_autobind
  fi
}

if [[ -z "${PROMPT_COMMAND:-}" ]]; then
  PROMPT_COMMAND="_cws_precmd"
elif [[ "$PROMPT_COMMAND" != *"_cws_precmd"* ]]; then
  PROMPT_COMMAND="_cws_precmd;$PROMPT_COMMAND"
fi
_cws_autobind

# add this to PS1, e.g.:
#   PS1='\u@\h $(cws_prompt_seg_bash)\w \$ '
