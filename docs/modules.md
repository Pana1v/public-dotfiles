# Modules

Each folder under `modules/` is one module: a `module.env` (description, dependencies),
an `apply.sh` and its files. `bootstrap.sh` picks modules from a preset and applies each one.

Apply a single module:

```bash
DOTFILES=$PWD bash modules/<name>/apply.sh
```

## Presets

| Preset | Machine |
|---|---|
| `minimal` | Terminal only: shell, git, tmux, CLI tools, dev toolchain; desktop untouched |
| `neon` | Neon orange work desktop: neon palette, dot-matrix wings, fleet + Linear deck |
| `personal` | Personal laptop: desktop rice, Obsidian, media apps, Google Tasks; no fleet or Linear widgets |
| `professional` | Work machine: desktop rice, fleet + Linear deck, robot ssh hosts; Google Tasks hidden |

## All modules

| Module | What it sets up | Depends on |
|---|---|---|
| `apps-desktop` | Desktop apps: Brave, Foxglove, VS Code, Cursor, terminals, snaps + flatpaks (OBS...) | apt-repos |
| `apps-dev` | Dev + CLI: build tools, docker, nvidia toolkit, tmux, fzf, rg, uv, nvm, rustup, Claude Code | apt-repos |
| `apt-repos` | Third-party apt sources + signing keys (Brave, Docker, VS Code, Cursor, gh, Tailscale...) | - |
| `browsers` | Rice every browser (Chrome, Brave, Chromium, Edge, Vivaldi, Firefox, LibreWolf, Zen; deb, flatpak, snap) in the active palette + start page | rice |
| `claude` | Claude Code status line (+ optional private claude-config repo from CLAUDE_CONFIG_REPO) | - |
| `cli-tools` | atuin, eza, bat, fd, delta, zoxide, lazygit, yazi, direnv, tealdeer, dust, duf, just, hyperfine, watchexec, fresh editor + shell hooks | - |
| `conky` | Conky widgets: Elysium, Claude usage, Linear, fleet, calendar, weather, now playing, audio, GitHub PRs + systemd units | fonts-cursors secrets |
| `cursor` | Cursor settings, rules (.mdc), mcp.json, cli-config, extensions | - |
| `fonts-cursors` | Fonts (Manrope, Nerd Symbols, Roboto, JetBrains Mono) + oreo-pink cursor | - |
| `git` | gitconfig (gh credential helper, lfs) + global gitignore | - |
| `gnome` | GNOME/Zorin settings via dconf: theme, keybindings, taskbar, extensions prefs, terminal, wallpaper | fonts-cursors |
| `gnome-extensions` | GNOME Shell extensions (14, incl. spotify-deck, sysmon-flair, stay-up) + enabled list | - |
| `mkdocs` | mk-please: serve any markdown folder as a live MkDocs site in the active palette (PDF, Obsidian edit, Mermaid zoom) | rice apps-dev |
| `obsidian` | Obsidian (snap, classic) + clone your notes vault (OBSIDIAN_REPO) + fill missing .obsidian config/plugins | - |
| `rice` | Tokyo Night rice: GTK/shell/icons, pop-shell tiling, kitty, starship, VS Code, Obsidian, Claude theme, rofi, Qt/Dolphin (Kvantum), wallpaper | gnome |
| `secrets` | ~/.config/secrets/*.env from templates (mode 600). Fill values by hand. | - |
| `shell` | bashrc, bash_aliases, profile, inputrc | - |
| `skills` | Agent skills and global instructions from the private repo, linked for Claude, Cursor, Qwen Code and Happy Agent | - |
| `spotify` | Spotify (user flatpak) themed with the rice palette through Spicetify | rice |
| `ssh` | ssh config host aliases from the private repo (example config on a public clone). No keys. | - |
| `terminator` | Terminator config + plugins (linear_issues, vscode_paths) | - |
| `tmux` | tmux.conf (mouse, 50k scrollback; keeps amr-docker marker so its setup.sh skips) | - |
| `vid2gif` | Vid2Gif GTK4 video trimmer: clones Pana1v/vid2gif, launcher + .desktop + gtk4 gst sink | - |
| `vscode` | VS Code settings, mcp.json, extensions | - |
