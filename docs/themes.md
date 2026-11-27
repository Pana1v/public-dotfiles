# Themes

The rice has seven palettes. Each palette is one file of role-to-hex pairs.
`switch-theme.sh` swaps the hexes in every themed file to the new palette.

## Palettes

Files live in `modules/rice/themes/<name>.palette`.

| Name | Look | Accent |
|------|------|--------|
| `ares` | Black and red program glow, cyan kept for good states | `#ff1f3d` |
| `blood` | Black, blood red accents, white text, amber for warnings | `#ec0b12` |
| `matrix` | Phosphor green on black | `#00ff41` |
| `mono` | Greyscale, colour only for state | `#f4f5f7` |
| `neon` | Warm blacks, neon orange glow, peach for good states | `#ff4d00` |
| `tokyonight` | Deep navy with soft blue and purple | `#7aa2f7` |
| `tron` | Near-black blue, light-cycle cyan, CLU orange for warnings | `#18e6ff` |

## Roles

Every palette defines the same 31 roles. The table covers the roles most
themed files use.

| Role | Used for |
|------|----------|
| `bg` | Main background |
| `card` | Raised panels and cards |
| `surface` | Input and list surfaces above the card |
| `select` | Selection highlight |
| `fg` | Primary text |
| `fg2` | Secondary text |
| `purple2` | Light tint for labels and secondary highlights |
| `dim2` | Muted text |
| `dim` | Dimmest readable text |
| `tab_fg` | Inactive tab text |
| `bright_black` | Borders and separators |
| `accent` | Main highlight: focus outline, links, active marks |
| `red` | Errors and destructive state |
| `yellow` | Warnings |
| `green` | Success and good state |
| `ansi_green`, `ansi_blue`, `ansi_cyan` | Terminal ANSI slots 2, 4, 6, so prompts, `ls` and git get distinct hues |

Colour rules for every palette:

- Text uses the white-to-grey roles (`fg`, `fg2`, `dim2`, `dim`, `purple2`).
- Red is for accents, borders and state only. Never for body text.
- Text contrast is at least 4.5:1 against its background.

## Switching

```bash
./modules/rice/switch-theme.sh <name>
```

1. Read `current-theme` to find the palette the files hold now.
2. Stop if `themes/<name>.palette` does not exist.
3. Skip the recolour if the target equals the current palette.
4. Assert both palettes share one role set and no palette reuses a hex.
5. Rewrite each file in `FILES`, swapping every current hex for the target role hex.
6. Write `<name>` to `current-theme`.
7. Rebuild the `bat` cache when `bat` is installed.
8. Copy the palette to `~/.config/rice/palette` for live readers.
9. Recolour and reload `sysmon-flair` when it is installed.
10. Set GTK, cursor, accent, shell theme name and wallpaper from the `@settings` lines.
11. Rebuild the Rice icon, Kvantum, cursor, VS Code and Cursor themes.
12. Update the btop theme, Obsidian theme and conky accent.
13. Restart conky services, send USR1 to kitty and re-source `~/.tmux.conf`.
14. Re-apply the browser start page and Spicetify when those are installed.

Restart these to see new colours: Terminator, Files, Claude Code and browsers.

!!! note
    The switch rewrites tracked files in the repo. Check `git diff` before you commit a switch.

### Runtime settings

| Setting | Effect |
|---------|--------|
| `@gtk` | GTK theme name |
| `@shell` | GNOME Shell theme name, optional |
| `@cursor` | Cursor theme, `Rice-cursors` is built per palette |
| `@accent` | GNOME accent colour, optional |
| `@btop` | btop colour theme |
| `@vscode` | VS Code and Cursor colour theme |
| `@wallpaper` | `image:<file>`, `color:<hex>` or none |
| `@taskbar_border` | Taskbar border colour |
| `@conky_accent` | Role name used as the conky accent |

`apply.sh` picks the palette from `RICE_THEME` in the environment or
`~/.config/dotfiles/local.env`. When unset, it uses `current-theme`.

## Adding a themed file

1. Put the active palette's hexes in the file. The swap only matches the current palette.
2. Add the file's path to the `FILES` array in `switch-theme.sh`.
3. Run a switch away and back to test it.

## Adding a palette

1. Create `modules/rice/themes/<name>.palette`.
2. Copy the 31 role lines from an existing palette. Keep the same role names.
3. Give every role a unique hex inside the palette.
4. Add `@gtk`, `@vscode`, `@btop`, `@wallpaper` and `@cursor`, copied from a palette that sets them.
5. Add `@shell`, `@accent`, `@conky_accent` and `@taskbar_border` as needed.
6. Run `switch-theme.sh <name>` and check the result.

## Tools

Tools in `modules/rice/tools/` build the assets that switches and apply runs.

| Tool | Builds |
|------|--------|
| `blackhole.py` | Ember black hole frames, still and loop for the wallpaper and lock screen |
| `folder-icons.py` | The Rice icon theme: Papirus-Dark with folders in the accent |
| `grid.py` | Tron grid wallpaper, lock-screen frames, Plymouth pieces, X avatar |
| `kvantum-theme.py` | The Rice Kvantum theme for Qt apps |
| `rain.py` | Digital rain loop for the lock screen |
| `recolor-assets.py` | Recoloured boot and greeter PNGs and text assets |
| `rice-cursors.py` | The Rice cursor theme, recoloured to the accent |
| `vscode-theme.py` | The Rice colour theme for VS Code and Cursor |

## Revert

`revert.sh` restores the pre-rice look: the old GTK theme, wallpaper, taskbar
settings and VS Code colour theme. It prints the steps it cannot automate.

!!! warning "Traps"
    - Never edit the active palette's hexes in place. Files hold the current hexes.
      Switch to another palette, edit, then switch back.
    - Every hex in a palette must be unique. The switch asserts this. A duplicate
      breaks the swap back.
    - A literal hex in a themed file that equals a palette hex gets swapped too.
      Keep stray hexes out of themed files.
    - The shell theme name stays `Rice`. GNOME does not reload the shell CSS when
      the name is set to the same value. Toggle the user-theme name to another
      value and back to reload it.
