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

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _cws_autobind
_cws_autobind
[[ -o interactive ]] && _cws_check_update

# add this to PROMPT (with `setopt prompt_subst`), e.g.:
#   PROMPT='%n@%m $(cws_prompt_seg)%~ > '
