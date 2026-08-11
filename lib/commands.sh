#!/usr/bin/env bash
# sourced, not executed. cws command implementations: add/rm/ls/theme/auth/
# reauth/trust/status/help, plus the `cws` dispatcher itself. shared verbatim
# between the zsh and bash entrypoints - no shell-specific syntax here.

_cws_auth_ok() {
  [[ -f "$1/.cws-auth" ]]
}

_cws_login_count() {
  command security dump-keychain 2>/dev/null | grep -c 'Claude Code-credentials-' || echo 0
}

CWS_BUILTIN_THEMES=(auto dark light dark-daltonized light-daltonized dark-ansi light-ansi)

# _cws_json_theme get|set|del <file> [value]
_cws_json_theme() {
  python3 - "$@" <<'PY'
import json, os, sys
op, f = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(f):
    try:
        with open(f) as fp:
            data = json.load(fp)
    except Exception as e:
        print(f"cws: cannot parse {f}: {e}", file=sys.stderr); sys.exit(1)
if op == "get":
    print(data.get("theme", ""))
    sys.exit(0)
if op == "set":
    data["theme"] = sys.argv[3]
elif op == "del":
    if "theme" not in data:
        sys.exit(0)
    del data["theme"]
os.makedirs(os.path.dirname(f) or ".", exist_ok=True)
tmp = f + ".tmp"
with open(tmp, "w") as fp:
    json.dump(data, fp, indent=2); fp.write("\n")
os.replace(tmp, f)
PY
}

# ~/.claude/settings.json is both personal's user settings AND the *project*
# settings for cwd=$HOME - a theme key there wins over every workspace's own
# theme whenever claude starts from $HOME. detect it.
_cws_theme_shadow() {
  local t
  t=$(_cws_json_theme get "$HOME/.claude/settings.json") || return 2
  [[ -n $t ]] || return 1
  echo "$t"
}

_cws_theme_warn_shadow() {
  local t
  t=$(_cws_theme_shadow) || return 0
  echo "cws: warning: ~/.claude/settings.json sets theme '$t'." >&2
  echo "     That file is also the *project* settings for \$HOME, so it overrides" >&2
  echo "     every workspace's theme when claude is launched from \$HOME." >&2
  echo "     Clear it with: cws theme --unshadow" >&2
}

_cws_theme() {
  _cws_load
  local name theme dir file

  if [[ "${1:-}" == --unshadow ]]; then
    local t
    if ! t=$(_cws_theme_shadow); then
      echo "no theme key in ~/.claude/settings.json - nothing shadowed."
      return 0
    fi
    _cws_json_theme del "$HOME/.claude/settings.json" || return 1
    echo "removed theme '$t' from ~/.claude/settings.json (personal now uses the default)."
    echo "other workspaces launched from \$HOME will use their own theme again."
    return 0
  fi

  if (( $# == 0 )); then
    echo "themes by workspace:"
    for name in "${_CWS_ORDER[@]}"; do
      dir=${_CWS_DIR[$name]}
      theme=$(_cws_json_theme get "$dir/settings.json")
      [[ -z $theme ]] && theme="<default (dark)>"
      if [[ $theme == custom:* && ! -f "$dir/themes/${theme#custom:}.json" ]]; then
        theme="$theme  !! missing $dir/themes/${theme#custom:}.json"
      fi
      if [[ "${CLAUDE_WORKSPACE:-}" == "$name" ]]; then
        echo "> $name: $theme"
      else
        echo "  $name: $theme"
      fi
    done
    _cws_theme_warn_shadow
    return 0
  fi

  if (( $# >= 2 )) && [[ -n "${_CWS_WS[$1]:-}" ]]; then
    name=$1; theme=$2
  else
    name=${CLAUDE_WORKSPACE:-}
    theme=$1
    if [[ -z $name ]]; then
      echo "cws theme: no active workspace; use: cws theme <workspace> <theme>" >&2
      return 1
    fi
  fi

  dir=${_CWS_DIR[$name]:-}
  if [[ -z $dir ]]; then
    echo "cws theme: unknown workspace '$name'" >&2
    return 1
  fi

  if [[ $theme == custom:* ]]; then
    local slug=${theme#custom:}
    if [[ ! -f "$dir/themes/$slug.json" ]]; then
      echo "cws theme: $dir/themes/$slug.json not found" >&2
      echo "  create it first (name/base/overrides JSON), or use /theme in claude" >&2
      return 1
    fi
  else
    local ok=0 b
    for b in "${CWS_BUILTIN_THEMES[@]}"; do [[ $b == "$theme" ]] && ok=1 && break; done
    if [[ $ok -eq 0 ]]; then
      echo "cws theme: '$theme' is not a builtin theme." >&2
      echo "  builtins: ${CWS_BUILTIN_THEMES[*]}" >&2
      echo "  custom:   custom:<slug>  (needs $dir/themes/<slug>.json)" >&2
      return 1
    fi
  fi

  file="$dir/settings.json"
  _cws_json_theme set "$file" "$theme" || return 1
  echo "$name -> theme '$theme'  (${file/#$HOME/~})"

  if [[ $dir == "$HOME/.claude" ]]; then
    echo "note: this file is also \$HOME's project settings, so other workspaces" >&2
    echo "      started from \$HOME will inherit '$theme'. Prefer leaving personal" >&2
    echo "      on the default, or start claude from a subdirectory." >&2
  else
    _cws_theme_warn_shadow
  fi
}

cws-status() {
  _cws_load
  local cur="${CLAUDE_WORKSPACE:-<unset>}"
  local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  echo "workspace:  $cur"
  echo "config_dir: $dir"
  local theme
  theme=$(_cws_json_theme get "$dir/settings.json")
  echo "theme:      ${theme:-<default (dark)>}"
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    echo "oauth:      STALE env token set - unset it (login would be overridden)"
  else
    echo "oauth:      account login (per-config keychain)"
  fi
  [[ $dir == "$HOME/.claude" ]] || _cws_theme_warn_shadow
}

_cws_help() {
  cat <<'EOF'
cws - portable multi-workspace Claude Code launcher

USAGE
  cws                      show active workspace
  cws <name>               set env for current shell (auto-rebind keeps it in sync)
  cws <name> <claude args> one-shot launch claude in that workspace
  cws ls                   list workspaces + bindings + colors
  cws theme                show each workspace's theme (+ shadow warning)
  cws theme <theme>        set theme for the active workspace
  cws theme <ws> <theme>   set theme for a named workspace
  cws theme --unshadow     drop the theme key from ~/.claude/settings.json
  cws add <name> [glob1,glob2...]  add a workspace: config dir, registry row,
                                    auto-assigned color, auto-generated theme
  cws auth <name>          claude auth login for that workspace's account
  cws reauth <name>        re-run login (same as cws auth)
  cws rm <name>            remove workspace (registry + token; keeps config dir)
  cws help                 this help

LAYOUT
  registry:     $CWS_ROOT/workspaces
                line format: name|configDir|keychainService|bindingGlobs|color
  config dirs:  ~/.claude-<name>  (personal -> ~/.claude)
  auth:         claude auth login, stored per-config-dir in macOS Keychain

BINDINGS
  Workspaces with bindings auto-switch when $PWD matches their glob. The first
  workspace with NO bindings is the default fallback (normally 'personal') -
  it's applied whenever no binding matches and nothing was set explicitly, so
  a fresh terminal always shows a labeled workspace instead of a bare icon.

COLORS & THEMES
  Every workspace gets a color (from a fixed palette, auto-assigned by 'cws
  add') and a matching generated Claude Code theme written to
  <configDir>/themes/<name>.json, set as that workspace's default theme.

NOTES
  Each workspace logs in with its own account via 'cws auth <name>'. claude
  stores login in the macOS Keychain per-config-dir, isolated between
  workspaces - no CLAUDE_CODE_OAUTH_TOKEN anywhere. NEVER set a token env var
  for a workspace that uses login: it would override the login at runtime.
EOF
}

_cws_ls() {
  _cws_load
  local name dir binds color cur="${CLAUDE_WORKSPACE:-<none>}" authmark
  echo "active: $cur   keychain logins: $(_cws_login_count)"
  for name in "${_CWS_ORDER[@]}"; do
    dir=${_CWS_DIR[$name]}
    binds=${_CWS_BIND[$name]:-}
    color=${_CWS_COLOR[$name]:-<none>}
    if _cws_auth_ok "$dir"; then
      authmark="login recorded"
    else
      authmark="login MISSING (run: cws auth $name)"
    fi
    local prefix="  "
    [[ "${CLAUDE_WORKSPACE:-}" == "$name" ]] && prefix="> "
    echo "${prefix}${name} -> ${dir/#$HOME/~} [color: $color]${binds:+ [bind: $binds]}  $authmark"
  done
}

_cws_add() {
  local name=$1; shift
  if [[ -z $name ]]; then
    echo "usage: cws add <name> [glob1,glob2...]" >&2
    return 1
  fi
  if [[ ! $name =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "cws add: name may only contain [a-zA-Z0-9_-]" >&2
    return 1
  fi
  _cws_load
  if [[ -n "${_CWS_WS[$name]:-}" ]]; then
    echo "cws add: workspace '$name' already exists" >&2
    return 1
  fi
  local dir binds=$1
  [[ $name == personal ]] && dir="$HOME/.claude" || dir="$HOME/.claude-$name"
  mkdir -p "$dir"

  local color
  color=$(_cws_next_color)

  if [[ -s "$CWS_REG" && $(tail -c1 "$CWS_REG" 2>/dev/null) != $'\n' ]]; then
    echo "" >> "$CWS_REG"
  fi
  echo "$name|$dir|claude-token-$name|${binds}|${color}" >> "$CWS_REG"
  _cws_load

  local themefile="$dir/themes/$name.json"
  _cws_gen_theme "$(_cws_titlecase "$name")" "$color" "$themefile"
  _cws_json_theme set "$dir/settings.json" "custom:$name"

  echo "workspace '$name' registered (config: $dir, color: $color)"
  echo "theme generated: ${themefile/#$HOME/~}"
  echo "authenticate it now with:  cws auth $name"
}

_cws_titlecase() {
  local s=$1
  s=${s//-/ }
  s=${s//_/ }
  local word first rest out=""
  for word in $s; do
    first=$(printf '%s' "${word:0:1}" | tr '[:lower:]' '[:upper:]')
    rest=${word:1}
    out+="$first$rest "
  done
  echo "${out% }"
}

_cws_auth() {
  local name=$1
  _cws_load
  if [[ -z "${_CWS_WS[$name]:-}" ]]; then
    echo "cws auth: unknown workspace '$name' (use: cws add $name first)" >&2
    return 1
  fi
  local dir=${_CWS_DIR[$name]}
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    echo "cws auth: CLAUDE_CODE_OAUTH_TOKEN is set in this shell - it would" >&2
    echo "override the login. Unset it first, then re-source your shell rc." >&2
    return 1
  fi
  echo "== claude auth login for workspace '$name' (config: $dir) =="
  echo "Sign in with the account for $name. Login is stored per-config-dir"
  echo "in the macOS Keychain, isolated from the other workspaces."
  command env CLAUDE_CONFIG_DIR="$dir" claude auth login
  local rc=$?
  if (( rc == 0 )); then
    : > "$dir/.cws-auth"
    echo "login done. verify with: cws $name && claude (then /status)"
  else
    echo "claude auth login exited $rc; nothing recorded." >&2
  fi
  return $rc
}

_cws_trust() {
  local target=${1:-$PWD}
  [[ $target != /* ]] && target="$PWD/$target"
  local dir="${CLAUDE_CONFIG_DIR:-}"
  local f
  if [[ -z $dir ]]; then
    f="$HOME/.claude.json"
  else
    f="$dir/.claude.json"
  fi
  python3 - "$target" "$f" <<'PY' || { echo "cws trust: failed to mark '$target' trusted" >&2; return 1; }
import json, sys, os
target, f = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(f):
    with open(f) as fp:
        data = json.load(fp)
data.setdefault("projects", {})
data["projects"].setdefault(target, {})["hasTrustDialogAccepted"] = True
tmp = f + ".tmp"
with open(tmp, "w") as fp:
    json.dump(data, fp)
os.replace(tmp, f)
PY
  echo "trusted '$target' (workspace ${CLAUDE_WORKSPACE:-<active>}, config $dir)"
}

_cws_rm() {
  local name=$1
  _cws_load
  if [[ $name == personal ]]; then
    echo "cws rm: cannot remove 'personal'" >&2
    return 1
  fi
  if [[ -z "${_CWS_WS[$name]:-}" ]]; then
    echo "cws rm: unknown workspace '$name'" >&2
    return 1
  fi
  local gone_dir=${_CWS_DIR[$name]}
  local gone_tok=${_CWS_TOK[$name]}
  local tmp="$CWS_REG.tmp"
  : > "$tmp"
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    case "$line" in
      "$name|"*) ;;
      *) echo "$line" >> "$tmp" ;;
    esac
  done < "$CWS_REG"
  mv "$tmp" "$CWS_REG"
  security delete-generic-password -s "$gone_tok" >/dev/null 2>&1 || true
  rm -f "$gone_dir/.cws-auth"
  _cws_load
  echo "removed '$name'. config dir left in place:"
  echo "  rm -rf $gone_dir   (only if you want it gone)"
  [[ "${CLAUDE_WORKSPACE:-}" == "$name" ]] && { unset CLAUDE_CODE_OAUTH_TOKEN CLAUDE_WORKSPACE; }
  _cws_autobind
}

cws() {
  _cws_load
  if (( $# == 0 )); then
    cws-status
    return
  fi
  local cmd=$1; shift
  case $cmd in
    add)    _cws_add "$@" ;;
    auth)   _cws_auth "$@" ;;
    reauth) _cws_auth "$@" ;;
    rm)     _cws_rm "$@" ;;
    ls)     _cws_ls ;;
    theme)  _cws_theme "$@" ;;
    status) cws-status ;;
    trust)  _cws_trust "$@" ;;
    help|--help|-h) _cws_help ;;
    *)
      if [[ -n "${_CWS_WS[$cmd]:-}" ]]; then
        _cws_apply "$cmd"
        _CWS_AUTO=""
        if (( $# > 0 )); then
          command claude "$@"
        fi
      else
        echo "cws: unknown '$cmd'. known: add|auth|reauth|rm|ls|theme|status|trust|help|${_CWS_ORDER[*]}" >&2
        return 1
      fi
      ;;
  esac
}
