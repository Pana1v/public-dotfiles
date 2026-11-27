# Rofi

Rofi is the launcher. Super+R opens it. Press Super+R again to close it.

- Tab or Alt+l moves to the next mode.
- Shift+Tab or Alt+h moves to the previous mode.
- Hover selects a row. A single click runs it.

Super+R toggles rofi with `pkill -x rofi`. The laptop Copilot key (Shift+Super+XF86TouchpadOff) opens the same launcher.

## Modes

| Mode | Prompt | What it does | How to use |
|------|--------|--------------|------------|
| drun | APPS | Desktop apps, sorted by launch history | Type a name, Enter launches |
| windows | WINDOWS | Every open window, Wayland included | Type a title, Enter focuses it |
| run | RUN | Rofi built-in. Runs a command | Type a command, Enter. Opens in terminator |
| calc | CALC | Calculator and unit conversion | Type expression, Enter, Enter again copies |
| ssh | SSH | Rofi built-in. SSH hosts | Pick a host, Enter. Opens in terminator |
| filebrowser | FILES | Rofi built-in file browser | Browse and pick |
| cheatsheet | KEYS | Shortcut sheet from gsettings | Read only. Enter closes rofi |
| power | POWER | Lock, suspend, log out, reboot, shut down | Pick a row. Power actions ask first |
| bots | BOTS | Fleet hosts: SSH, tmuxinator, Foxglove | Pick a host, then an action |
| emoji | EMOJI | Emoji picker by name or keyword | Type a name, Enter copies |
| time | TIME | World clock and time conversion | Type a time, a zone, or both |
| grab | GRAB | Colour picker and screenshot | Pick a row, finish in the portal UI |

## calc

- Script mode cannot evaluate while you type.
- Type an expression and press Enter to see the answer row.
- Press Enter on the answer row to copy the bare value.
- Units and number bases work.

| Input | Meaning |
|-------|---------|
| `5 ft to m` | Unit conversion |
| `0x1f to dec` | Base conversion |

## cheatsheet

- Read only. Bindings come from gsettings at each open.
- Rebinding a key updates the sheet without edits.
- Sections: SWITCH, FOCUS, TILING, TILE MODE, WORKSPACES, WINDOW.
- Keypad arrow copies are hidden.

## power

- Rows: Lock, Suspend, Log out, Reboot, Shut down.
- Lock and suspend run at once.
- Log out, reboot and shut down show a `Yes, ...` row and a Back row.
- Actions run detached, so they finish after rofi closes.

## windows

- Rofi's built-in window mode reads X11 clients and misses native Wayland windows.
- This mode asks the `rofi-focus` GNOME Shell extension over D-Bus.
- Each row shows title, app and workspace. `all` means on every workspace.

## calc, emoji and time copy with xclip

Several modes copy the picked value. See the Traps box below.

## bots

- Hosts come from the private fleet list. Each line holds a label and an address.
- The same list feeds the conky fleet widget.
- A host opens an action menu with SSH, Tmuxinator, Foxglove and Back.

| Action | Result |
|--------|--------|
| SSH | Opens an ssh session in terminator |
| Tmuxinator | Lists local project files, or reads them from the host |
| Foxglove | Opens foxglove-studio on the bot websocket port |

- SSH targets resolve through `~/.ssh/config` when a matching entry exists.

## emoji

- Names and keywords come from the Unicode CLDR English annotations.
- Search by name or keyword, for example `smile` or `flag`.
- Enter copies the emoji.
- Needs `unicode-cldr-core`.

## time

- Empty query shows IST, Amsterdam and UTC.
- Type `HH:MM` to read the time in the machine zone.
- Add a zone to read the time there.
- Type a zone alone to add its row.

| Input | Result |
|-------|--------|
| `14:30` | 14:30 in the machine zone |
| `9:00 cet` | 9:00 Amsterdam time |
| `tokyo` | Adds a Tokyo row |

- Aliases: `ist`, `cet`, `cest`, `utc`.
- Other names match the timezone list, such as `America/New_York`.
- Enter copies the row text.

## grab

- Pick colour: opens the portal colour picker. Copies a hex value such as `#FF0080`.
- Screenshot to clipboard: opens the portal screenshot UI. Copies a PNG.
- Rofi closes 0.4 s before the capture, so it is not in the shot.
- A request with no answer closes after `GRAB_TIMEOUT` seconds. Default is 120.

## Requirements

| Package | Used by |
|---------|---------|
| rofi | Launcher |
| qalc | calc |
| xclip | calc, time, emoji, grab |
| unicode-cldr-core | emoji |
| rofi-focus extension | windows |
| PyGObject (`gi`) | windows, grab. Not in the rice `packages.apt`, verify it is installed |
| terminator | run, ssh, bots |
| tmuxinator, foxglove-studio | bots actions (optional) |

The rice module installs rofi, qalc, xclip and unicode-cldr-core from `modules/rice/packages.apt`.

## Self-tests

Scripts with a `SELFTEST` branch run their checks and print `ok`.

```bash
SELFTEST=1 ~/.config/rofi/scripts/tz.sh
SELFTEST=1 ~/.config/rofi/scripts/bots.sh
SELFTEST=1 ~/.config/rofi/scripts/emoji.py
SELFTEST=1 ~/.config/rofi/scripts/grab.py
```

- `tz.sh` checks zone aliases and UTC to IST and JST conversion.
- `bots.sh` checks host list parsing.
- `emoji.py` and `grab.py` run Python asserts.
- `calc.sh`, `keys.sh`, `power.sh` and `windows.py` have no self-test.

## Traps

!!! warning "Traps"

    - **Wayland clipboard**: rofi runs on XWayland, so scripts copy with `xclip`.
    - **grab screenshots**: `gnome-screenshot` hangs when a script calls it under a portal permission. Grab uses the portal in interactive mode.
    - **emoji names**: needs `unicode-cldr-core`. Without it, the mode shows a `cldr missing` message.
    - **bots list**: reads the private fleet list. A clone without that file shows an empty BOTS list.
