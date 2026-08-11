#!/usr/bin/env bash
# sourced, not executed. generates a full custom Claude Code theme JSON from a
# single accent hex color, matching the override-key schema Claude Code expects
# (name/base/overrides). requires python3.

# _cws_gen_theme <display-name> <accent-hex> <outfile>
_cws_gen_theme() {
  local name=$1 accent=$2 outfile=$3
  mkdir -p "$(dirname "$outfile")"
  python3 - "$name" "$accent" "$outfile" <<'PY'
import colorsys, json, sys

name, accent, outfile = sys.argv[1], sys.argv[2], sys.argv[3]

def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))

def rgb_to_hex(rgb):
    return '#%02x%02x%02x' % tuple(max(0, min(255, round(c * 255))) for c in rgb)

def shift(h, dl=0.0, ds=0.0):
    r, g, b = hex_to_rgb(h)
    hue, l, s = colorsys.rgb_to_hls(r, g, b)
    l = max(0.0, min(1.0, l + dl))
    s = max(0.0, min(1.0, s + ds))
    return rgb_to_hex(colorsys.hls_to_rgb(hue, l, s))

def dark_bg(h, lightness, sat=0.55):
    r, g, b = hex_to_rgb(h)
    hue, _, _ = colorsys.rgb_to_hls(r, g, b)
    return rgb_to_hex(colorsys.hls_to_rgb(hue, lightness, sat))

r, g, b = hex_to_rgb(accent)
hue, _, _ = colorsys.rgb_to_hls(r, g, b)
deg = hue * 360
buckets = [
    (0, 15, 'red'), (15, 45, 'orange'), (45, 70, 'yellow'), (70, 170, 'green'),
    (170, 200, 'cyan'), (200, 255, 'blue'), (255, 290, 'indigo'),
    (290, 345, 'violet'), (345, 360, 'red'),
]
rainbow = next(n for lo, hi, n in buckets if lo <= deg < hi)

theme = {
    "name": name,
    "base": "dark",
    "overrides": {
        "claude": accent,
        "claudeShimmer": shift(accent, dl=0.12),
        "text": shift(accent, dl=0.55, ds=-0.35),
        "inverseText": dark_bg(accent, 0.10, 0.55),
        "inactive": shift(accent, dl=0.05, ds=-0.5),
        "inactiveShimmer": shift(accent, dl=0.2, ds=-0.4),
        "subtle": shift(accent, dl=-0.15, ds=-0.45),
        "suggestion": shift(accent, dl=-0.05),
        "permission": shift(accent, dl=-0.05),
        "permissionShimmer": shift(accent, dl=0.05),
        "remember": shift(accent, dl=0.1),
        "success": "#34d399",
        "error": "#ff7b72",
        "warning": "#fbbf24",
        "warningShimmer": "#fcd34d",
        "merged": shift(accent, dl=0.12),
        "promptBorder": accent,
        "promptBorderShimmer": shift(accent, dl=0.12),
        "planMode": shift(accent, dl=-0.05),
        "autoAccept": accent,
        "bashBorder": shift(accent, dl=-0.05),
        "ide": shift(accent, dl=0.1),
        "fastMode": shift(accent, dl=0.25, ds=-0.2),
        "diffAdded": "#14532d",
        "diffAddedDimmed": "#113822",
        "diffAddedWord": "#4ade80",
        "diffRemoved": "#7f1d1d",
        "diffRemovedDimmed": "#3f1414",
        "diffRemovedWord": "#ff7b72",
        "userMessageBackground": dark_bg(accent, 0.09),
        "userMessageBackgroundHover": dark_bg(accent, 0.13),
        "bashMessageBackgroundColor": dark_bg(accent, 0.10),
        "memoryBackgroundColor": dark_bg(accent, 0.14),
        "selectionBg": shift(accent, dl=-0.05),
        "rate_limit_fill": accent,
        "rate_limit_empty": dark_bg(accent, 0.22, 0.15),
        "briefLabelYou": "#7aa2f7",
        "briefLabelClaude": accent,
        f"{rainbow}_FOR_SUBAGENTS_ONLY": accent,
        f"rainbow_{rainbow}": shift(accent, dl=0.1),
    },
}

with open(outfile, "w") as fp:
    json.dump(theme, fp, indent=2)
    fp.write("\n")
PY
}
