#!/usr/bin/env bash
# sourced, not executed. palette + deterministic color assignment for workspaces.

CWS_PALETTE=(
  "#c084fc" # violet
  "#60a5fa" # blue
  "#4ade80" # green
  "#fb923c" # orange
  "#f87171" # red
  "#22d3ee" # cyan
  "#fbbf24" # yellow
  "#f472b6" # pink
  "#2dd4bf" # teal
  "#818cf8" # indigo
  "#a3e635" # lime
  "#fb7185" # rose
)

# echoes the first palette color not already used by any workspace in the
# loaded registry (_CWS_COLOR must be populated via _cws_load first). cycles
# back to the start of the palette (still picking the least-recently-used one)
# once every color is taken.
_cws_next_color() {
  local c used name
  for c in "${CWS_PALETTE[@]}"; do
    used=0
    for name in "${_CWS_ORDER[@]}"; do
      [[ "${_CWS_COLOR[$name]:-}" == "$c" ]] && { used=1; break; }
    done
    if [[ $used -eq 0 ]]; then
      echo "$c"
      return 0
    fi
  done
  # every palette color is in use: pick one deterministically by count so
  # repeated `cws add` calls still spread out reasonably.
  local n=${#_CWS_ORDER[@]}
  echo "${CWS_PALETTE[$(( n % ${#CWS_PALETTE[@]} ))]}"
}
