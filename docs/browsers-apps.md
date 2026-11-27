# Browsers and apps

The rice paints browsers and desktop apps with the active palette.
Each module reads the palette file and writes its own config.
Switching palettes reruns the modules that need it.

## Browsers

| Browser | What gets themed | Manual step |
|---------|------------------|-------------|
| Chrome (deb, flatpak) | Theme, dark mode, colour seed, start page, new tab wallpaper | None |
| Edge (deb, flatpak) | Theme, dark mode, colour seed, start page | None |
| Brave (deb, flatpak) | Theme, dark mode, colour seed, start page, new tab wallpaper | Load the Rice theme once |
| Chromium (deb, flatpak, snap) | Theme, dark mode, colour seed, start page, new tab wallpaper | Load the Rice theme once |
| Vivaldi (deb) | Theme, dark mode, colour seed, start page | Load the Rice theme once |
| Firefox (deb, flatpak, snap) | Toolbar, tabs, menus, new tab page, scrollbars, selection | None |
| LibreWolf, Zen (deb, flatpak) | Same as Firefox | None |
| Thunderbird (deb, flatpak) | Folder pane, message list, reader, tabs, message bodies | None |

Every profile of each installed browser gets the rice.
A browser without a profile folder is skipped.

## Chrome and Edge theme

The module builds an unpacked theme at `~/.config/chrome-rice-theme`.

- Frame image: a 512 x 48 PNG.
- Base colour is the palette black.
- A faint grid sits under an accent glow that rises to a horizon line.
- Inactive windows get the same image at half strength.
- Active tab uses the toolbar colour, which is lighter than the black strip.
- Tab text and the new tab page use palette roles.

The module writes the theme link into each profile's `Preferences` file.
Chrome and Edge then load the theme on the next start.
No click is needed for these two.

Brave, Chromium, and Vivaldi still need a one-time load:

1. Open `chrome://extensions`.
2. Turn on Developer mode.
3. Click Load unpacked.
4. Select `~/.config/chrome-rice-theme`.

Edge and Vivaldi keep their own new tab page.

Run the self-check after changing the code:

```bash
python3 -I modules/browsers/files/rice_browsers.py selfcheck
```

## Firefox and Thunderbird

Firefox-family profiles get two generated files in `chrome/`:

| File | Effect |
|------|--------|
| `userChrome.css` | Toolbar, tabs, menus, URL field |
| `userContent.css` | New tab page with the wallpaper, selection, scrollbars on every site |

A marked block in `user.js` sets:

- Dark theme.
- Stylesheets on.
- The start page as home.
- No sponsored new tab content.

Thunderbird gets `userChrome.css` over its `--layout-*` variables.
It also gets a `user.js` block for dark theme, stylesheets, and dark message bodies.

The first run keeps a backup next to each changed file:

- `Preferences.pre-rice`
- `user.js.pre-rice`

## Sites

Extensions cannot be set from outside the browser.
The module writes two files for you to import once per browser:

| File | Import path | Effect |
|------|-------------|--------|
| `~/.local/share/rice/darkreader.json` | Dark Reader > Settings > Advanced > Import Settings | Palette colours on every site |
| `~/.local/share/rice/stylus.json` | Stylus > Manage > Import | GitHub styles from its Primer colour tokens |

Dark Reader skips `github.com`, `gist.github.com`, and `linear.app`.
Stylus covers GitHub.

Linear reads colours from JavaScript.
Set them by hand in Settings > Preferences > Interface theme > Custom.
The apply output prints the background, text, and accent values.

Re-import both files after a palette switch.

## Apps

| App | How it gets the palette |
|-----|-------------------------|
| VS Code (and Cursor) | `vscode-theme.py` maps the Tron template colours onto palette roles and builds a "Rice" theme. `switch-theme.sh` sets `workbench.colorTheme` to Rice. |
| Obsidian | `theme.css` holds palette hexes. `switch-theme.sh` copies it into the vault at `.obsidian/themes/Rice` and sets it as the active theme. |
| Claude Code | `~/.claude/themes/rice.json` links to the rice file. Its hexes are recoloured on each switch. Select the theme in the claude-config settings. |
| Spotify | Spicetify theme "Rice" with a `color.ini` generated from the palette. Applied only when Spotify is closed. |
| mpv | `mpv.conf` and `script-opts` hold palette colours and a Space Mono OSD. The cli-tools module links them. |
| Qt apps | `qt5ct` reads `colors/rice.conf`. Style is Kvantum. `kvantum-theme.py` recolours KvFlat into `~/.config/Kvantum/Rice`. |
| GTK 4 and libadwaita | `gtk-4.0/gtk.css` sets the libadwaita named colours. |
| GTK 3 | The palette's `gtk` setting picks the GTK theme. `gtk-3.0/gtk.css` sets titlebar colours. |

## Run it

From the repository root:

```bash
DOTFILES=$PWD bash modules/browsers/apply.sh
```

Close each browser first.
The script skips a running browser and prints a reminder.

## Traps

!!! warning "Traps"

    - A running browser rewrites `Preferences` on exit.
      Its exit undoes the patch, so apply skips it. Close it, then rerun.
    - Branded Chrome on Linux ignores user-level External Extensions.
      It reads them only from root-owned folders.
      The module writes the theme link into `Preferences` instead.
    - Palette changes need a browser restart.
      The theme and prefs load on the next start.
