#!/usr/bin/env python3
"""cws statusLine renderer.

Configured via settings.json:
  {"statusLine": {"type": "command", "command": "<CWS_HOME>/lib/statusline.sh"}}

Reads Claude Code's session JSON on stdin (see the statusLine docs), and
reads the active workspace's color out of the private registry
($CWS_ROOT/workspaces, same file lib/registry.sh reads) via $CLAUDE_WORKSPACE
- keeps the workspace badge in sync with the prompt segment without needing
to know workspace names at write time.
"""
import json
import os
import sys

RESET = "\033[0m"
DIM = "\033[2m"
RED = "\033[31m"


def hex_to_rgb(h):
    h = (h or "999999").lstrip("#")
    if len(h) != 6:
        h = "999999"
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def fg_for_bg(r, g, b):
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    return (20, 20, 20) if lum > 0.6 else (240, 240, 240)


def ansi_bg(r, g, b):
    return f"\033[48;2;{r};{g};{b}m"


def ansi_fg(r, g, b):
    return f"\033[38;2;{r};{g};{b}m"


def workspace_color(ws, cws_root):
    reg = os.path.join(cws_root, "workspaces")
    if not ws or not os.path.exists(reg):
        return "#999999"
    try:
        with open(reg) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("|")
                if len(parts) >= 5 and parts[0] == ws and parts[4]:
                    return parts[4]
    except OSError:
        pass
    return "#999999"


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}

    ws = os.environ.get("CLAUDE_WORKSPACE", "")
    cws_root = os.environ.get("CWS_ROOT", os.path.expanduser("~/.config/claude-workspaces"))
    color = workspace_color(ws, cws_root)
    r, g, b = hex_to_rgb(color)
    fr, fg, fb = fg_for_bg(r, g, b)
    badge = f"{ansi_bg(r, g, b)}{ansi_fg(fr, fg, fb)} {ws} {RESET}" if ws else ""

    model = (data.get("model") or {}).get("display_name", "?")
    workspace = data.get("workspace") or {}
    cwd = workspace.get("current_dir") or data.get("cwd", "")
    dirname = os.path.basename(cwd.rstrip("/")) or cwd

    cw = data.get("context_window") or {}
    pct = cw.get("used_percentage")
    pct = int(pct) if pct is not None else 0
    # workspace accent color, except once context is nearly full - red always
    # wins there since it's a warning, not a theme choice.
    bar_color = RED if pct >= 90 else ansi_fg(r, g, b)
    width = 10
    filled = pct * width // 100
    bar = "#" * filled + "-" * (width - filled)
    ctx_str = f"{bar_color}[{bar}]{RESET} {pct}% ctx"

    sep = f"  {DIM}|{RESET}  "
    line1 = sep.join([f"{badge} {model}".strip(), dirname, ctx_str])

    effort = (data.get("effort") or {}).get("level")
    cost_data = data.get("cost") or {}
    cost = cost_data.get("total_cost_usd") or 0
    dur_ms = cost_data.get("total_duration_ms") or 0
    mins, secs = divmod(int(dur_ms) // 1000, 60)
    five_h = ((data.get("rate_limits") or {}).get("five_hour") or {}).get("used_percentage")

    parts2 = []
    if effort:
        parts2.append(f"{DIM}effort{RESET} {effort}")
    parts2.append(f"{DIM}cost{RESET} ${cost:.2f}")
    parts2.append(f"{DIM}time{RESET} {mins}m{secs}s")
    if five_h is not None:
        parts2.append(f"{DIM}5h limit{RESET} {five_h:.0f}%")
    line2 = sep.join(parts2)

    print(line1)
    print(line2)


if __name__ == "__main__":
    main()
