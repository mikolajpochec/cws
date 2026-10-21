<h1 align="center">cws</h1>

<p align="center"><b>One shell, many Claude Code accounts.</b><br>
<code>cd</code> into a project and Claude Code is already logged in as the right account.</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-24292f?style=flat-square"></a>
  <img alt="zsh and bash" src="https://img.shields.io/badge/shell-zsh%20%7C%20bash-89e051?style=flat-square">
  <img alt="macOS and Linux" src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey?style=flat-square">
  <img alt="Claude Code" src="https://img.shields.io/badge/for-Claude_Code-7a4dff?style=flat-square">
</p>

<p align="center">
  <a href="#install"><b>Install</b></a> &nbsp;·&nbsp;
  <a href="#quick-start"><b>Quick start</b></a> &nbsp;·&nbsp;
  <a href="#commands"><b>Commands</b></a>
</p>

<p align="center"><img width="900" alt="Two terminals in different workspaces, each with its own colored badge, theme and status line" src="https://github.com/user-attachments/assets/2ccb86bc-8a2f-4a31-946d-b797d9c36d51"></p>

## Why

You have a personal Claude account and a work one (maybe a client's too). Claude Code keeps one
login per config directory, so switching means logging out and in, or juggling
`CLAUDE_CONFIG_DIR` by hand. cws does it for you:

- **Isolated workspaces.** Each one is its own config dir with its own login, settings, MCP
  servers, history and theme.
- **Switches by directory.** Bind `~/dev/work` to `work` and every shell inside it uses that account.
  Leave and you're back on your default.
- **You always know where you are.** Each workspace gets a color: a prompt badge, a matching
  Claude Code theme generated from it, and a status line in the same color.
- **Never touches credentials.** Logins stay in the OS keychain, stored by `claude` itself.
- **Plain shell.** zsh or bash plus `python3`, nothing to compile.

## Install

```sh
git clone https://github.com/mikolajpochec/cws.git ~/dev/cws
~/dev/cws/install.sh
```

Then add the badge to your prompt and open a new terminal:

```sh
# zsh (needs: setopt prompt_subst)
PROMPT='%n@%m $(cws_prompt_seg)%~ > '

# bash
PS1='\u@\h $(cws_prompt_seg_bash)\w \$ '
```

The installer is safe to run again. A fresh install creates two example workspaces, `personal`
(`~/.claude`) and `work` (`~/.claude-work`).

> [!NOTE]
> bash support needs bash 4+. macOS ships 3.2, so run `brew install bash` or use zsh.

## Quick start

```sh
cws add client-x            # new workspace: config dir, color and theme
cws auth client-x           # log in with that account, once
cws bind client-x ~/dev/x   # ~/dev/x and everything under it use client-x
cd ~/dev/x && claude        # already the right account
```

Need another account for a single command? `cws work -p "summarize this repo"` runs `claude` in
`work` without switching your shell.

## Commands

| Command | What it does |
|---|---|
| `cws` | Show the active workspace |
| `cws <name>` | Switch this shell to a workspace |
| `cws <name> <claude args>` | Run `claude` once in a workspace |
| `cws ls` | List workspaces, bindings, colors and login status |
| `cws add <name> [globs] [--color #rrggbb]` | Add a workspace; color and theme are picked for you, or seeded from `--color` |
| `cws bind <name> [dir]` | Bind a directory and its subtree (current dir if omitted) |
| `cws auth <name>` | Log that workspace in to its account |
| `cws theme [<ws>] [<theme>]` | Show or set a workspace's theme |
| `cws trust [path]` | Mark a path trusted in the active workspace |
| `cws search-session <keywords>` | Fuzzy-search past sessions across workspaces (`-w a,b` to narrow) |
| `cws rm <name>` | Remove a workspace (its config dir is kept) |
| `cws update` | Pull the latest cws |
| `cws help` | Full reference |

## Details

<details>
<summary><b>Status line</b></summary>

Every workspace's `settings.json` gets `lib/statusline.sh` as its `statusLine`, drawn in the
workspace color:

```
 personal  Sonnet 5  |  project-dir  |  [####------] 42% ctx
effort high  |  cost $0.12  |  time 12m5s  |  5h limit 24%
```

Fields a session doesn't have are left out. A `statusLine` you set yourself is never replaced.
</details>

<details>
<summary><b>Binding with globs</b></summary>

`cws bind` binds one exact directory. To match several by name, pass globs when creating the
workspace:

```sh
cws add client-x '**/dev/*client-x*'
```

When several workspaces match, the most specific glob (most non-wildcard characters) wins, so
`~/dev/*client-x*` beats a catch-all `~/*`; ties go to the earlier entry. When nothing matches, cws
falls back to the first workspace with no bindings (`personal` by default).
</details>

<details>
<summary><b>Colors and themes</b></summary>

`cws add` takes the next unused color from a 12-color palette (`lib/colors.sh`). `lib/theme-gen.sh`
derives a full Claude Code theme from it, about 40 color keys via HSL math, writes it to
`<configDir>/themes/<name>.json` and sets it as that workspace's theme. Pass `--color #rrggbb` to
pick the color yourself; the theme is generated from it the same way:

```sh
cws add assistant --color '#d4a72c'   # gold
```
</details>

<details>
<summary><b>Searching sessions</b></summary>

`cws search-session <keywords...>` (alias `cws search`) fuzzy-searches the Claude Code sessions of
every workspace: titles, project path, git branch, your prompts and the chat text. It lists the best
matches, each with a ready-to-paste resume command (`cd <project> && cws <ws> --resume <id>`).
Matching is typo-tolerant; sessions that match every keyword rank first.

```sh
cws search-session window queue ratio
cws search-session -w personal,work -n 20 auth bug   # or --workspace=personal,work
```

Extracted text is cached in `$CWS_ROOT/.search-cache` (per transcript, keyed by mtime + size), so
repeat searches only re-read changed sessions.
</details>

<details>
<summary><b>Updating</b></summary>

`cws update` fetches, shows what's new and fast-forwards your clone. Shells check for updates
offline at startup and print a one-line nudge when you're behind; a silent background fetch runs
once a week so that check stays fresh without slowing startup.
</details>

<details>
<summary><b>Where your setup lives</b></summary>

This repo holds only code. Your workspace list lives in `$CWS_ROOT` (default
`~/.config/claude-workspaces/workspaces`), one line per workspace:

```
name|configDir|keychainService|bindings|color
```

- `bindings`: comma-separated globs matched against `$PWD`; the most specific match wins; empty
  means never auto-bound.
- `color`: hex like `#c084fc`, used for the badge and as the theme seed.
</details>

<details>
<summary><b>Code layout</b></summary>

```
shell/cws.zsh      zsh entrypoint (chpwd hook + prompt var)
shell/cws.bash     bash entrypoint (PROMPT_COMMAND + PS1)
lib/registry.sh    registry parsing, env apply/clear, directory auto-bind
lib/colors.sh      palette + color assignment
lib/theme-gen.sh   accent color -> full theme JSON
lib/commands.sh    the cws command and its subcommands
lib/prompt.sh      prompt segments for zsh and bash
lib/statusline.sh  Claude Code status line renderer
install.sh         idempotent installer
```
</details>

## License

[MIT](LICENSE)
