#!/usr/bin/env bash
# lib/registry.sh - sourced (not executed) by either bash 4+ or zsh.
# Loads the pipe-delimited workspace registry into associative arrays and
# provides the apply/clear/autobind primitives shared by the bash and zsh
# entrypoints.
#
# Registry line format (color is optional, may be missing on old lines):
#   name|configDir|keychainService|bindings|color

declare -gA _CWS_WS _CWS_DIR _CWS_TOK _CWS_BIND _CWS_COLOR
declare -ga _CWS_ORDER
: "${_CWS_AUTO:=}"

# zsh's `case` does not glob-expand a pattern that came from a variable
# unless GLOB_SUBST is set (bash always does) - needed so the `case "$PWD"
# in $m)` binding match below behaves the same in both shells.
[ -n "${ZSH_VERSION:-}" ] && setopt GLOB_SUBST 2>/dev/null

CWS_REG="${CWS_REG:-${CWS_ROOT:-$HOME/.config/claude-workspaces}/workspaces}"

_cws_load() {
  _CWS_WS=(); _CWS_DIR=(); _CWS_TOK=(); _CWS_BIND=(); _CWS_COLOR=(); _CWS_ORDER=()
  [ -f "$CWS_REG" ] || return
  local name dir tok binds color
  while IFS='|' read -r name dir tok binds color || [ -n "$name" ]; do
    [ -z "$name" ] && continue
    case "$name" in '#'*) continue ;; esac
    _CWS_WS[$name]=1
    _CWS_DIR[$name]=$dir
    _CWS_TOK[$name]=$tok
    _CWS_BIND[$name]=$binds
    _CWS_COLOR[$name]=$color
    _CWS_ORDER+=("$name")
  done < "$CWS_REG"
}

_cws_default_workspace() {
  local name
  for name in "${_CWS_ORDER[@]}"; do
    if [ -z "${_CWS_BIND[$name]:-}" ]; then
      echo "$name"
      return
    fi
  done
}

_cws_apply() {
  local name=$1 dir
  dir=${_CWS_DIR[$name]:-}
  unset CLAUDE_CODE_OAUTH_TOKEN
  if [ -n "$dir" ] && [ "$dir" != "$HOME/.claude" ]; then
    export CLAUDE_CONFIG_DIR="$dir"
  else
    unset CLAUDE_CONFIG_DIR
  fi
  export CLAUDE_WORKSPACE="$name"
}

_cws_clear_env() {
  unset CLAUDE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN CLAUDE_WORKSPACE
  _CWS_AUTO=
}

# BUG FIX: the original only applied a workspace on a binding match and never
# fell back to a default, so a fresh shell left CLAUDE_WORKSPACE unset even
# though it was effectively running "personal" (unset CLAUDE_CONFIG_DIR ==
# personal's dir). Step 4 below applies the registry's first unbound entry
# whenever nothing else claimed the workspace, so the prompt can label it.
_cws_autobind() {
  [ -f "$CWS_REG" ] || return
  _cws_load

  local name binds rest m

  for name in "${_CWS_ORDER[@]}"; do
    binds=${_CWS_BIND[$name]:-}
    [ -z "$binds" ] && continue
    # split on commas with plain parameter expansion (no arrays/read -a,
    # since zsh's `read` has no bash-compatible -a array flag)
    rest="$binds,"
    while [ -n "$rest" ]; do
      m=${rest%%,*}
      rest=${rest#*,}
      [ -z "$m" ] && continue
      case "$PWD" in
        $m)
          [ "${CLAUDE_WORKSPACE:-}" = "$name" ] || _cws_apply "$name"
          _CWS_AUTO="$name"
          return
          ;;
      esac
    done
  done

  # no binding matched: drop only an auto-applied workspace, keep explicit ones
  if [ -n "${_CWS_AUTO:-}" ] && [ "${CLAUDE_WORKSPACE:-}" = "$_CWS_AUTO" ]; then
    _cws_clear_env
  fi

  # nothing bound and nothing explicit/auto left set -> fall back to default
  if [ -z "${CLAUDE_WORKSPACE:-}" ]; then
    name=$(_cws_default_workspace)
    if [ -n "$name" ]; then
      _cws_apply "$name"
      _CWS_AUTO="$name"
    fi
  fi
}
