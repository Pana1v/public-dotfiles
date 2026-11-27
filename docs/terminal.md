# Terminal

Terminal emulators, prompt, command-line tools and their shared Ares palette.

## Terminals

Three layers draw the terminal. Each reads hexes from the same palette.

| Tool | Themed | Key bindings |
|------|--------|--------------|
| Terminator | 16-colour palette, background, cursor, red title bars | Alt+1..9 switch tab |
| Terminator | | Alt+H, J, K, L move left, down, up, right between splits |
| Terminator | | Ctrl+Shift+B broadcast to all panes |
| Terminator | | Ctrl+Shift+M turn broadcast off |
| kitty | 16 colours, tab bar, borders, selection | No custom keys set in the file |
| tmux | Top status bar, red session-name pill | Default prefix, Ctrl+b |

Terminator config: `modules/terminator/files/config`.

- Background is `#0a0303` at 0.85 darkness, transparent.
- Font is JetBrains Mono 11. Scrollback is 50000 lines.
- Copy on selection is on. The cursor is an I-beam and does not blink.
- Title bars: red when transmitting, light grey when receiving, dark when inactive.

kitty config: `modules/rice/files/kitty/current-theme.conf`.

- Opaque window, 12 px padding, block cursor that does not blink.
- Tab bar uses `|` separators. Active tab is red.

tmux config: `modules/tmux/files/tmux.conf`.

- Mouse on. History limit 50000 lines.
- Sources `tokyonight.conf` when present. That file puts the status bar on top.

## Prompt

Starship draws the prompt from `modules/rice/files/starship.toml`. It shows a
single line with a directory pill (last 3 path parts), a git branch and status
pill, a Python venv segment, and a command duration. The duration shows only
for commands over 2 seconds. The `❯` symbol turns pink on success and red on
error. Glyphs need a Nerd Font, installed by the fonts module.

## Tools

Packages from `modules/cli-tools/packages.apt` and `packages.snap`, plus the
tools that apply.sh builds or installs directly.

| Tool | What for | Command or alias |
|------|----------|------------------|
| eza | Colour `ls` with git status and icons | `ls`, `ll`, `la`, `lt`, or `eza` |
| bat | `cat` with syntax highlight | `batcat` (Ubuntu name), linked as `bat` |
| git-delta | Git diff pager, Ares syntax theme | Set in `delta.gitconfig`, runs under `git diff` |
| fd-find | Fast file finder | `fdfind` (Ubuntu name), linked as `fd` |
| zoxide | Jump to frequent directories | `z foo`, pick with fzf: `zi foo` |
| lazygit | Git terminal UI | `lg` or `lazygit` |
| tealdeer | Short man pages (tldr) | `tldr <command>` |
| direnv | Load per-directory env files | Hooks into the prompt. Run `direnv allow` in a project |
| du-dust | Disk usage tree | `dust` |
| duf | Disk free table | `duf` |
| hyperfine | Benchmark commands | `hyperfine 'cmd'` |
| just | Command runner for `justfile` | `just <recipe>` |
| glow | Render Markdown in the terminal | `glow file.md` |
| chafa | Show images as text art | `chafa image.png` |
| ffmpegthumbnailer | Video thumbnails | `ffmpegthumbnailer -i in.mp4 -o out.png` |
| gping | Ping with a live latency graph | `gping host` |
| procs | Process list | `procs` |
| tokei | Lines of code by language | `tokei` |
| yazi (snap) | Terminal file manager | `y` (wrapper, see below) or `yazi` |
| bandwhich (snap) | Network use per process | `sudo bandwhich` |
| atuin | Shell history search | Ctrl+R. Up arrow stays bash history |
| watchexec | Rerun a command on file change | `watchexec -- <cmd>` |
| fresh | Terminal text editor | `fresh`. x86_64 only |
| btop | System monitor | `btop`. Theme file per palette |
| fastfetch | System info banner | `fastfetch`. Shown at shell start if `banner.py` is missing |

`bandwhich` may need the snap interface first:
`sudo snap connect bandwhich:network-observe`.

## Aliases

Defined in `modules/cli-tools/files/cli-tools.bash`. They load after the
generic `bashrc` aliases, so these win for `ll` and `la`.

| Name | Expands to | Use |
|------|------------|-----|
| `ls` | `eza --group-directories-first --icons=auto` | Directory-first listing |
| `ll` | `eza -l --git --group-directories-first --icons=auto --time-style=relative` | Long listing with git status |
| `la` | `eza -la` with the same options as `ll` | Long listing with hidden files |
| `lt` | `eza -T --level=2 --git-ignore --icons=auto` | Tree, two levels, skips ignored files |
| `lg` | `lazygit` | Open git UI |

Shell function and zoxide commands in the same file:

- `y` opens yazi. On quit, the shell `cd`s to the directory yazi ended in.
- `z` and `zi` come from zoxide `init`. Plain `cd` is unchanged.

## Themed TUIs

The palette hexes live in these files. `modules/rice/switch-theme.sh <name>`
rewrites each hex to the target palette's value for the same role.

| File | What it colours |
|------|-----------------|
| `modules/rice/files/kitty/current-theme.conf` | kitty colours and tab bar |
| `modules/rice/files/starship.toml` | Prompt segments |
| `modules/rice/files/tmux/tokyonight.conf` | tmux status bar |
| `modules/terminator/files/config` | Terminator palette and title bars |
| `modules/cli-tools/files/cli-tools.bash` | `LS_COLORS` and `less` colours |
| `modules/cli-tools/files/eza/theme.yml` | eza colours |
| `modules/cli-tools/files/yazi/theme.toml` | yazi colours |
| `modules/cli-tools/files/bat/themes/Ares.tmTheme` | bat syntax colours |
| `modules/cli-tools/files/delta.gitconfig` | delta diff tints |
| `modules/cli-tools/files/glow/ares.json` | glow Markdown style |
| `modules/cli-tools/files/atuin/themes/ares.toml` | atuin UI |
| `modules/cli-tools/files/lazygit.yml` | lazygit selected-line tone |
| `modules/rice/files/mpv/*` | mpv OSD and menu |

`btop` has one theme file per palette in `modules/rice/files/btop/`. The
switch does not rewrite them. `fastfetch` names ANSI colours, so it follows
the terminal palette.

## Install

Run from the repo root:

```bash
DOTFILES=$PWD bash modules/cli-tools/apply.sh
```

- Needs `sudo` for apt and snap installs.
- Links every config above into `~/.config` and `~/.local/bin`.
- Builds watchexec with cargo when cargo exists. Skips it otherwise.
- Installs the fresh release tarball on x86_64 only.
- Adds one `source` line to `~/.bashrc`, and one git include for delta.

!!! warning "Traps"

    - Ubuntu ships bat and fd as `batcat` and `fdfind`. cli-tools links them
      to `bat` and `fd` in `~/.local/bin`. Scripts depend on those names.
    - Restart Terminator and kitty after a theme switch. They read colours
      at start.
    - Tools without theme files take colours from the terminal palette.
      Their output changes with the terminal, not with `switch-theme.sh`.
    - After a theme switch, `bat` needs a cache rebuild. The switch script
      runs `bat cache --build`. Rerun `batcat cache --build` by hand if
      you edit `Ares.tmTheme` directly.
