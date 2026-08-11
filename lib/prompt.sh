#!/usr/bin/env bash
# lib/prompt.sh - sourced (not executed) by either bash 4+ or zsh.
# Assumes registry.sh has already been sourced and _cws_load has already run
# at least once (the entrypoint's job), so _CWS_COLOR et al. are populated.

# zsh prompt segment: claude icon + colored workspace badge. Safe to embed in
# PROMPT with prompt_subst. Glyph is wrapped in %{...%} (zero-width) so zsh's
# width calc ignores it, keeping later prompt segments aligned.
cws_prompt_seg() {
  local icon=$'\Uf069'
  if [[ -z ${CLAUDE_WORKSPACE:-} ]]; then
    print -r -- "%F{#d97757}%{${icon}%}%f "
    return
  fi
  local color=${_CWS_COLOR[$CLAUDE_WORKSPACE]:-}
  [[ -z $color ]] && color='#999999'
  print -r -- "%F{$color}[%F{#d97757}%{${icon}%}%f %F{$color}${CLAUDE_WORKSPACE}]%f "
}

# hex "#rrggbb" -> "R;G;B" for truecolor ANSI sequences.
_cws_hex_to_rgb() {
  local hex=${1#\#} r g b
  ((r=16#${hex:0:2}))
  ((g=16#${hex:2:2}))
  ((b=16#${hex:4:2}))
  echo "$r;$g;$b"
}

# bash prompt segment equivalent, for use in PS1. ANSI codes must be wrapped
# in \[...\] (bash's non-printing-escape markers) so the line-length
# calculation used for cursor placement / history search stays correct.
cws_prompt_seg_bash() {
  local icon=$'\xef\x81\xa9'
  if [ -z "${CLAUDE_WORKSPACE:-}" ]; then
    printf '\[\033[38;2;217;119;87m\]%s\[\033[0m\] ' "$icon"
    return
  fi
  local color=${_CWS_COLOR[$CLAUDE_WORKSPACE]:-}
  [ -z "$color" ] && color='#999999'
  local rgb
  rgb=$(_cws_hex_to_rgb "$color")
  printf '\[\033[38;2;%sm\][\[\033[38;2;217;119;87m\]%s\[\033[0m\] \[\033[38;2;%sm\]%s]\[\033[0m\] ' \
    "$rgb" "$icon" "$rgb" "$CLAUDE_WORKSPACE"
}
