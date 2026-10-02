#!/usr/bin/env zsh
# cws zsh entrypoint. source this from ~/.zshrc with CWS_HOME set to this
# repo's checkout path (install.sh wires this up for you):
#
#   export CWS_HOME="$HOME/dev/cws"
#   [ -f "$CWS_HOME/shell/cws.zsh" ] && source "$CWS_HOME/shell/cws.zsh"
#
# private data (which workspaces exist, their config dirs) lives outside this
# repo in $CWS_ROOT (default ~/.config/claude-workspaces) - nothing here.

: ${CWS_HOME:?"cws.zsh: set CWS_HOME to this repo path before sourcing"}
: ${CWS_ROOT:=$HOME/.config/claude-workspaces}
export CWS_HOME CWS_ROOT
CWS_REG="$CWS_ROOT/workspaces"

source "$CWS_HOME/lib/registry.sh"
source "$CWS_HOME/lib/colors.sh"
source "$CWS_HOME/lib/theme-gen.sh"
source "$CWS_HOME/lib/commands.sh"
source "$CWS_HOME/lib/prompt.sh"

# Shells opened before a cws change keep running the old functions, so a
# fix to e.g. binding matching never reached them. On every cd, re-source
# cws when any of its files changed since this shell loaded them.
zmodload -F zsh/stat b:zstat 2>/dev/null
_cws_src_sig() {
  local -a t
  zstat -A t +mtime -- "$CWS_HOME"/lib/*.sh "$CWS_HOME/shell/cws.zsh" 2>/dev/null
  REPLY="${t[*]}"
}
_cws_chpwd() {
  local REPLY
  _cws_src_sig
  if [[ "$REPLY" != "$_CWS_SRC_SIG" ]]; then
    _CWS_RELOADING=1 source "$CWS_HOME/shell/cws.zsh"
  else
    _cws_autobind
  fi
}
_cws_src_sig; _CWS_SRC_SIG=$REPLY

autoload -Uz add-zsh-hook
add-zsh-hook -d chpwd _cws_autobind
add-zsh-hook chpwd _cws_chpwd
_cws_autobind
[[ -o interactive && -z "${_CWS_RELOADING:-}" ]] && _cws_check_update

# add this to PROMPT (with `setopt prompt_subst`), e.g.:
#   PROMPT='%n@%m $(cws_prompt_seg)%~ > '
