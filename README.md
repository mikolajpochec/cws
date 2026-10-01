# cws — Claude Workspace Switcher
<img width="1237" height="845" alt="image" src="https://github.com/user-attachments/assets/2ccb86bc-8a2f-4a31-946d-b797d9c36d51" />

Switch between multiple Claude Code accounts/config dirs (`personal`, `work`,
whatever you add) in your shell, with auto-binding by directory, per-workspace
colored prompt badges, and auto-generated matching Claude Code themes.

Each workspace maps to its own `CLAUDE_CONFIG_DIR` (a separate `~/.claude-*`
directory), so logins, settings, MCP servers, history, and themes are fully
isolated per account. Login is stored per-config-dir in the OS keychain by
`claude` itself — cws never touches or stores credentials.

## Requirements

- zsh or bash 4+ (macOS ships bash 3.2 — install a newer one for bash support:
  `brew install bash`; zsh has no such requirement)
- `python3` (theme generation, JSON settings edits, status line)

## Install

```sh
git clone https://github.com/mikolajpochec/cws.git ~/dev/cws
cd ~/dev/cws
./install.sh
```

This is idempotent: it won't overwrite an existing workspace registry or an
existing cws block in your shell rc files. On a fresh install it creates two
example workspaces, `personal` (→ `~/.claude`) and `work` (→ `~/.claude-work`),
each with an auto-generated theme, and wires sourcing into `~/.zshrc` and
`~/.bashrc`.

bash support needs bash 4+ (associative arrays) — macOS ships bash 3.2, so
on a Mac without a newer bash (`brew install bash`) the installer skips the
`~/.bashrc` block and prints a note; zsh has no such requirement.

After installing, add the prompt segment to your prompt:

```sh
# zsh (needs: setopt prompt_subst)
PROMPT='%n@%m $(cws_prompt_seg)%~ > '

# bash
PS1='\u@\h $(cws_prompt_seg_bash)\w \$ '
```

Open a new terminal and you should see a colored `[  personal]` badge.

## Usage

```
cws                      show active workspace
cws <name>               set env for current shell (auto-rebind keeps it in sync)
cws <name> <claude args> one-shot launch claude in that workspace
cws ls                   list workspaces + bindings + colors
cws add <name> [globs]   add a workspace - color + theme auto-assigned
cws bind <name> [dir]    bind a directory (+ subtree) to a workspace - current dir if omitted
cws rm <name>            remove a workspace (registry + token; config dir kept)
cws auth <name>          claude auth login for that workspace's account
cws theme                show/set a workspace's theme
cws trust [path]         mark a path trusted in the active workspace's config
cws search-session <kw>  fuzzy-search past sessions across workspaces (-w a,b to narrow)
cws update               pull the latest cws release
cws help                 full command reference
```

### Binding a workspace to a directory

For an existing workspace, bind an actual directory (its exact path plus
subtree, no glob-writing needed):

```sh
cd ~/dev/client-x
cws bind client-x          # binds the current directory
cws bind client-x ~/other  # or bind an arbitrary directory
```

For a glob pattern instead (e.g. matching several directories by name), pass
it when creating the workspace:

```sh
cws add client-x '**/dev/*client-x*'
```

Either way, `cd`-ing into a bound path auto-switches to that workspace;
`cd`-ing back out returns to whatever the fallback workspace is (the first
entry in the registry with no bindings — `personal` by default).

### Colors & themes

`cws add` auto-assigns the next unused color from a 12-color palette
(`lib/colors.sh`) and generates a full Claude Code custom theme
(`lib/theme-gen.sh`, derives the theme's ~40 color keys from the one accent
color via HSL math) written to `<configDir>/themes/<name>.json`, set as that
workspace's default theme. No manual theme authoring needed.

### Status line

`cws add` (and `install.sh` for the two example workspaces) also wires each
workspace's `settings.json` to `lib/statusline.sh` as its `statusLine`
command. It shows, in the workspace's badge color:

```
 personal  Sonnet 5  |  project-dir  |  [####------] 42% ctx
effort high  |  cost $0.12  |  time 12m5s  |  5h limit 24%
```

workspace badge, model, dir, and context-window bar on line one; effort
level, session cost/duration, and 5-hour rate limit on line two
(fields that aren't present in a given session, like `effort` or
`rate_limits`, are just omitted). It reads the badge color back out of the
private registry via `$CLAUDE_WORKSPACE`/`$CWS_ROOT`, both exported by
`shell/cws.zsh`/`cws.bash`, so it stays in sync with the prompt segment
without hardcoding any workspace name. Never overwrites a `statusLine` you've
set to something else — it only claims the key when it's unset or already
points at `statusline.sh`.

### Searching sessions

`cws search-session <keywords...>` (alias `cws search`) fuzzy-searches the
Claude Code sessions of every workspace - titles, project path, git branch,
your prompts and the chat text - and lists the best matches, each with a
ready-to-paste resume command (`cd <project> && cws <ws> --resume <id>`).
Matching is typo-tolerant; sessions that match every keyword rank first.

```sh
cws search-session window queue ratio
cws search-session -w personal,work -n 20 auth bug   # or --workspace=personal,work
```

Extracted text is cached in `$CWS_ROOT/.search-cache` (per transcript, keyed
by mtime + size), so repeat searches only re-read changed sessions.

### Updating

`cws update` fetches `origin`, shows what's new, and fast-forwards `$CWS_HOME`
(only works for a `git clone` install, the recommended path above - it
declines cleanly on a vendored/copied checkout with no remote). Each
interactive shell also does a passive, offline check at startup - it never
hits the network itself, just reads whatever `origin/<branch>` was last
fetched to, and prints a one-line nudge if you're behind. Once a week it
kicks a silent background `git fetch` so that check has fresh data next time,
without ever blocking shell startup.

## Layout

```
shell/cws.zsh      zsh entrypoint (chpwd hook + prompt var)
shell/cws.bash     bash entrypoint (PROMPT_COMMAND + PS1)
lib/registry.sh    registry parsing, env apply/clear, directory auto-bind
lib/colors.sh      palette + color assignment
lib/theme-gen.sh   accent-color -> full theme JSON generator
lib/commands.sh    add/rm/ls/theme/auth/trust/status/help + the cws dispatcher
lib/prompt.sh      cws_prompt_seg (zsh) / cws_prompt_seg_bash (bash)
lib/statusline.sh  Claude Code statusLine renderer (workspace-colored)
install.sh         idempotent installer
```

This repo holds only the *code*. Your actual workspace list (account names,
config dir paths, directory bindings, colors) lives outside the repo in
`$CWS_ROOT` (default `~/.config/claude-workspaces/workspaces`) and is never
read from or written into this repo — safe to keep this repo public while
keeping your account setup private.

## Registry format

```
name|configDir|keychainService|bindings|color
```

- `bindings`: comma-separated glob patterns matched against `$PWD`. When
  several workspaces match, the most specific glob (most non-wildcard
  characters) wins, so `~/dev/*client-x*` beats a catch-all `~/*`; ties go to
  the earlier entry. Empty =
  never auto-bound by directory; the first such entry is the fallback
  workspace used when nothing else matches.
- `color`: hex string (`#c084fc`), used for the prompt badge and as the seed
  for that workspace's generated theme.

## License

MIT — see [LICENSE](LICENSE).
