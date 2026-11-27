# GNOME extensions

The rice ships its own GNOME Shell extensions and a fixed enabled list.
Most house extensions draw into the top bar, the desktop, or the Terminator windows.
Third-party extensions come from upstream and are copied the same way.

## How they install

| Step | What happens |
|------|--------------|
| Source | `modules/gnome-extensions/files/<uuid>/` |
| Copy | `apply.sh` copies the tree to `~/.local/share/gnome-shell/extensions/` |
| Schemas | `glib-compile-schemas` runs on every `schemas/` folder |
| Enabled list | `enabled.txt` sets `enabled-extensions` through `gsettings` |
| Disabled list | `disabled.txt` sets `disabled-extensions` |
| Version gate | Extensions whose `shell-version` lacks the running GNOME major are left off |
| Backdrop swap | With `RICE_BACKDROP=ember`, `grid-live` becomes `blackhole-live` |

The files are copied, not linked.
The Extension Manager updates extensions in place, so a link would be overwritten.
Run the module, then log out and back in. The script prints that reminder.

## Top bar layout

Left to right, from the `gnome-shell.css` header:

```
[01 02 ..] [machine graphs] [dot-matrix clock] [tray, system menu] [music pill]
 ws-numbers  sysmon-flair     cet-clock         tray icons           spotify-deck
```

The music pill sits at the right end of the top bar, on one line.

## House extensions

| Extension | What it does | Where it shows |
|-----------|--------------|----------------|
| blackhole-live | Animated Ember black hole, GPU shader | Desktop wallpaper and GDM login dialog |
| cet-clock | Central European time next to the date | Top bar, center box |
| clip-deck | Clipboard history for text, links, colours, images and screenshots | Super+V card, pastes into the previous window |
| conky-glass | Real blur behind conky widgets, shaped to their panels | Desktop, behind conky |
| grid-live | Animated Tron grid, GPU shader | Desktop wallpaper and GDM login dialog |
| power-extras | Battery time left, and reboot to UEFI Setup or Windows | Quick Settings battery, power menu |
| rofi-focus | Raises and focuses rofi, lists windows over D-Bus | Rofi window and window switcher |
| show-desktop | Super+D minimises all windows on the workspace, next press restores | Keyboard shortcut |
| spotify-deck | Spotify strip with art, title, spectrum and transport | Top bar, right end, one line |
| stay-up | Toggles always-on-top on the focused window | Keyboard shortcut, default Super+T |
| sysmon-flair | CPU, memory, network, temperature and GPU with sparklines | Top bar, click for detail menu |
| term-landscape | Ember black hole drawn in ASCII behind Terminator windows | Terminator windows, focused one animates |
| ws-numbers | Clickable workspace numbers in place of Activities dots | Top bar, left box |

### Notes

#### spotify-deck

- One-line pill at the right end of the top bar.
- Progress hairline is tinted by the album cover.
- Transport controls appear on hover.
- Spectrum comes from `cava` when installed, otherwise a synthesised waveform.

#### sysmon-flair

- Reads `~/.config/rice/palette` live.
- `switch-theme.sh` rewrites that file and toggles the extension to repaint.

#### term-landscape

- Only the focused Terminator window animates.
- Other windows freeze on their last frame, dimmed.

#### clip-deck

- Super+V opens a keyboard-first card.
- Enter pastes into the window you came from.
- Terminal windows get Ctrl+Shift+V, from a built-in list.
- Password manager entries are not stored.

## Third-party

| Extension | Description | In enabled list |
|-----------|-------------|-----------------|
| Resource Monitor | CPU, RAM, swap, disk, network and GPU in the top bar | No |
| Blur my Shell | Blur for the top panel, dash and overview | Yes |
| Boost Volume | Boosts volume above limits | Yes |
| Clipboard History | Searchable clipboard history panel | Off |
| Compiz alike magic lamp effect | Magic lamp window effect | No |
| Compiz windows effect | Wobbly windows effect | No |
| Desktop Cube | 3D desktop cube effect | No |
| Dynamic Music Pill | Pill-shaped music player with visualiser | Yes |
| Extension List | Manages extensions from the top panel | Yes |
| Gnome Clipboard | Clipboard history with pinning | Off |
| Live Lock Screen | Video, GIF or image as lock screen | Yes |
| Pop Shell | Tiling window manager | Yes |
| spotify-tray | Panel button with Spotify playback info | Yes |
| Space Bar | i3-like workspaces bar | Off |
| Spotify Controller | Popup player with lyrics and cover art | No |
| Spotify Controls | Spotify controls and track info in the top bar | No |
| Volume Boost | Toggle to boost volume above limits | Yes |

## Updating an extension

1. Edit the file in `modules/gnome-extensions/files/<uuid>/`.
2. Copy it into `~/.local/share/gnome-shell/extensions/<uuid>/`.
3. Log out and back in.

GNOME caches extension JavaScript for the session.
Log out and back in to load changed `extension.js` files.
Stylesheet-only changes reload with `gnome-extensions disable` and `enable`.

## Traps

!!! warning "Traps"

    - `shell-version` in `metadata.json` must list the running GNOME major.
      Otherwise GNOME drops the extension, and `apply.sh` leaves it off.
    - Wayland cannot restart the shell in place.
      Log out and back in. Alt+F2 then `r` works on Xorg only.
    - The shell CSS reloads when `switch-theme.sh` sets the `user-theme` name.
      Editing `gnome-shell.css` alone does nothing until then.
