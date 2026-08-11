#!/usr/bin/env bash
# cws installer. idempotent - safe to re-run; never overwrites an existing
# registry or shell-rc block.
#
# usage:
#   ./install.sh                 # installs into $HOME, CWS_ROOT defaults to
#                                 # ~/.config/claude-workspaces
#   CWS_ROOT=/tmp/cws-test ./install.sh   # install against a scratch root,
#                                         # for testing without touching a
#                                         # real setup
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CWS_ROOT="${CWS_ROOT:-$HOME/.config/claude-workspaces}"
CWS_REG="$CWS_ROOT/workspaces"

echo "cws installer"
echo "  repo:     $REPO_ROOT"
echo "  CWS_ROOT: $CWS_ROOT"
echo

mkdir -p "$CWS_ROOT"

if [[ -f "$CWS_REG" ]]; then
  echo "registry already exists at $CWS_REG - leaving it alone."
else
  echo "creating example registry (personal, work)..."
  personal_color="#c084fc"
  work_color="#60a5fa"
  personal_dir="$HOME/.claude"
  work_dir="$HOME/.claude-work"
  mkdir -p "$personal_dir" "$work_dir"

  cat > "$CWS_REG" <<EOF
# claude-workspaces registry: name|configDir|keychainService|bindings(comma-separated globs)|color
# bindings match against \$PWD. the first entry with empty bindings is the
# fallback workspace, applied when nothing else matches (see lib/registry.sh).
personal|$personal_dir|claude-token-personal||$personal_color
work|$work_dir|claude-token-work||$work_color
EOF

  # generate starter themes for the two example workspaces
  source "$REPO_ROOT/lib/theme-gen.sh"
  _cws_gen_theme "Personal" "$personal_color" "$personal_dir/themes/personal.json"
  _cws_gen_theme "Work" "$work_color" "$work_dir/themes/work.json"
  python3 - "$personal_dir/settings.json" <<'PY'
import json, os, sys
f = sys.argv[1]
data = {}
if os.path.exists(f):
    with open(f) as fp:
        data = json.load(fp)
data["theme"] = "custom:personal"
os.makedirs(os.path.dirname(f) or ".", exist_ok=True)
with open(f, "w") as fp:
    json.dump(data, fp, indent=2); fp.write("\n")
PY
  python3 - "$work_dir/settings.json" <<'PY'
import json, os, sys
f = sys.argv[1]
data = {}
if os.path.exists(f):
    with open(f) as fp:
        data = json.load(fp)
data["theme"] = "custom:work"
os.makedirs(os.path.dirname(f) or ".", exist_ok=True)
with open(f, "w") as fp:
    json.dump(data, fp, indent=2); fp.write("\n")
PY
  echo "  wrote $CWS_REG"
  echo "  wrote $personal_dir/themes/personal.json, $work_dir/themes/work.json"
fi

_install_rc_block() {
  local rc=$1 shellname=$2 entrypoint=$3
  local marker_begin="# >>> cws >>>"
  local marker_end="# <<< cws <<<"

  if [[ -f "$rc" ]] && grep -qF "$marker_begin" "$rc"; then
    echo "$rc already has a cws block - leaving it alone."
    return
  fi

  touch "$rc"
  {
    echo ""
    echo "$marker_begin"
    echo "export CWS_HOME=\"$REPO_ROOT\""
    echo "export CWS_ROOT=\"$CWS_ROOT\""
    echo "[ -f \"\$CWS_HOME/shell/$entrypoint\" ] && source \"\$CWS_HOME/shell/$entrypoint\""
    echo "$marker_end"
  } >> "$rc"
  echo "added cws to $rc ($shellname)"
}

_install_rc_block "$HOME/.zshrc" zsh cws.zsh

if command -v bash >/dev/null 2>&1 && [[ "$(bash -c 'echo "${BASH_VERSINFO[0]}"')" -ge 4 ]]; then
  _install_rc_block "$HOME/.bashrc" bash cws.bash
else
  echo "skipping ~/.bashrc: system bash is ${BASH_VERSION:-<3.2, macOS default}, cws needs bash 4+"
  echo "  (install one with: brew install bash) - zsh is fully wired either way."
fi

cat <<EOF

done. next steps:
  - open a new terminal (or: source ~/.zshrc / source ~/.bashrc)
  - embed the prompt segment in your PROMPT/PS1, e.g.
      zsh:  PROMPT='%n@%m \$(cws_prompt_seg)%~ > '
      bash: PS1='\u@\h \$(cws_prompt_seg_bash)\w \\\$ '
  - cws auth work        # log in to the 'work' example workspace
  - cws add <name> [globs]   # add more workspaces (color + theme auto-assigned)
  - cws help
EOF
