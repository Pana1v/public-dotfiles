# Conky widgets

The desktop widgets are drawn by conky. The main setup is two wings
and two deck strips. Each wing is a column of matte cards. Every card
has a number, starting at 01.

The module lives in `modules/conky/`. `apply.sh` links the Lua files to
`~/.config/conky` and copies the systemd units to
`~/.config/systemd/user`. Each machine picks its widgets in
`~/.config/dotfiles/local.env` with `CONKY_WIDGETS`. The default is
`wings deck`.

## Layout

The left wing runs cards 01 to 06. The two deck strips take 07 and 08.
The right wing starts at 09.

```
+-------------------------------------------------------------+
|        |  07 FLEET   top strip, host chips          |       |
| LEFT   |--------------------------------------------| RIGHT |
| WING   |  clock slot, off by default                |  WING |
| 01-06  |--------------------------------------------| 09-14 |
|        |  08 LINEAR  bottom strip, issue queue      |       |
+-------------------------------------------------------------+
```

Wing layout rules, from `Common/wing.lua`:

- Each card has a fixed height `h`, or a height from `size()`.
- One card can be `flex`. It takes the spare height.
- With no flex card, spare height is shared evenly.
- The gap is 14 px. It drops to 10 px when space is tight.
- The optional Activity card is dropped when the wing is full.

## Cards

| No. | Card | Where | Shows | Source |
|---|---|---|---|---|
| 01 | Systems | Left | CPU, GPU and memory gauges, NPU when reported | `sysmon` feed |
| 02 | Devices | Left | Battery of headsets, mice, keyboards and buds | `devices`, `cmf_buds` feeds |
| 03 | Audio | Left | Default output and input, volume, mute | `audio` feed |
| 04 | Now playing | Left | Track, artist, play state, position rings | `now_playing` feed |
| 05 | Claude | Left | 5 h and 7 d Claude Code limit use and reset | `~/.claude/rate-cache.json` |
| 06 | Activity | Left, optional | 60 s CPU and network graphs, disk bar | `sysmon` feed |
| 07 | Fleet | Deck top | Up or down state and latency per host | `fleet.tsv` (ping sweep) |
| 08 | Linear | Deck bottom | Issue queue, started issues first | `linear` feed |
| 09 | Weather | Right | Conditions, feels-like, rain, sun times, next hours | `weather` feed |
| 10 | Calendar | Right | Month grid for the current month | none, reads the date |
| 11 | Agenda | Right | Today and tomorrow events, countdown | `events` feed |
| 12 | GitHub | Right | Open PRs, review state, CI state | `github_prs` feed |
| 13 | Docker | Right | Running containers, uptime, CPU, memory | `docker` feed |
| 14 | Tasks | Right, not in professional profile | Open and recently done Google Tasks | `tasks` feed |

Card rules:

- Agenda shrinks to 100 px when no calendar is connected.
- GitHub takes the freed height in that case.
- Tasks loads only when `PROFILE` is not `professional`.
- Numbers follow list order. Inserting a card renumbers the cards after it.

## Widgets

Every folder under `modules/conky/files/conky/` is one widget. Some
are wing cards. Some also run as standalone windows with their own
`.conf` and systemd unit.

| Widget | Shows | Data source |
|---|---|---|
| Agenda | Today and tomorrow events, countdown to the next one | `events` feed, GNOME calendars through evolution-data-server |
| Calendar | Month grid for the current month | None, reads the date only |
| ClaudeUsage | Session and weekly Claude Code limit use and reset | `~/.claude/rate-cache.json`, read directly |
| Clock | Ring clock with weather line and next event | `weather` and `events` feeds |
| CmfBuds | Default audio output and input, volume, mute | `audio` feed, WirePlumber through `fetch_audio.py` |
| Devices | Battery of linked peripherals and buds | `devices` feed (UPower), `cmf_buds` feed |
| Docker | Container counts, uptime, CPU, memory, ROS domain | `docker` feed, `fetch_docker.py` |
| Elysium | Five module cards: clock, system, disk, network, time zone | Conky system variables and `${exec}` calls |
| FleetStatus | Ping state of hosts from your private fleet list | `fleet.tsv`, written by `ping_hosts.py` |
| GithubPRs | Open PRs, mine and review requested, review and CI state | `github_prs` feed, `gh` CLI |
| LinearWidget | Active Linear issues in a large panel | `fetch_issues.py` run through `${exec}` |
| NowPlaying | Track, artist, play state, position rings | `now_playing` feed, `playerctl` |
| Systems | CPU, GPU and memory gauges, 60 s graphs | `sysmon` feed, `fetch_system.py` |
| Tasks | Open and recently done Google Tasks | `tasks` feed, evolution-data-server |
| Weather | Conditions, feels-like, rain chance, sun times | `weather` feed, wttr.in |

Elysium still calls `conky_parse` with `${exec}` on each tick. The
LinearWidget also runs its fetch through `${exec}`. Both go against
the rule in the Traps section.

## Data feeders

Widgets never fetch data while drawing. A slow call in the draw loop
freezes the whole window. `io.popen` from Lua can also crash conky.

`Common/feeds.py` runs under `conky-feeds.service`. It starts one
thread per source. Each thread runs its script on its own interval.
The output goes to `~/.cache/conky/<name>.tsv`. The widgets only read
those files.

| Feeder | Interval | Script | Snapshot |
|---|---|---|---|
| weather | 600 s | `Weather/fetch_weather.py` | `weather.tsv` |
| github_prs | 120 s | `GithubPRs/fetch_prs.py` | `github_prs.tsv` |
| linear | 120 s | `LinearWidget/fetch_issues.py` | `linear.tsv` |
| now_playing | 1 s | `NowPlaying/now_playing.sh` | `now_playing.tsv` |
| cmf_buds | 15 s | `CmfBuds/fetch_buds.py` | `cmf_buds.tsv` |
| audio | 1 s | `CmfBuds/fetch_audio.py` | `audio.tsv` |
| devices | 5 s | `Devices/fetch_devices.py` | `devices.tsv` |
| events | 60 s | `Agenda/fetch_events.py` | `events.tsv` |
| tasks | 60 s | `Tasks/fetch_tasks.py` | `tasks.tsv` |
| docker | 10 s | `Docker/fetch_docker.py` | `docker.tsv` |
| sysmon | 1 s | `Systems/fetch_system.py` | `sysmon.tsv` |

Feeder rules:

- Each snapshot starts with a `ts` line holding the last success time.
- The file is written to a temp file, then renamed. Readers never see a half file.
- Empty output keeps the previous snapshot.
- A failed run retries after 30 s, not after the full interval.
- A run that hangs is stopped after 120 s.
- In the professional profile the tasks feeder is removed and its cache is deleted.

Two sources run outside `feeds.py`:

- `fleet.tsv` comes from `ping_hosts.py` under `fleet-ping.service`. It sweeps every 15 s.
- The Claude card reads `~/.claude/rate-cache.json` directly. Claude Code writes that file.

## Restarting

Each widget has a user unit named `<name>-conky.service`. The wings and
decks follow the same pattern.

```bash
systemctl --user restart wing-left-conky.service
systemctl --user restart wing-right-conky.service
systemctl --user restart deck-top-conky.service
systemctl --user restart deck-bottom-conky.service
systemctl --user restart conky-feeds.service
```

List the running conky units:

```bash
systemctl --user list-units '*conky*'
```

Restart a wing after a change to its Lua file. Restart `conky-feeds`
after a change to `feeds.py`. The profile is read once per window, so
restart after changing `PROFILE` or `CONKY_PROFILE`.

`apply.sh` restarts the wings, decks and feeds after each install.
`reposition-on-monitor-change.sh` restarts widgets on monitor changes.
It does this for every `*-conky.service`. Conky keeps the window
position from startup, so a monitor change would leave widgets off
screen otherwise.

## Adding a card

1. Create `Widgets/<name>.lua` with `update` and `draw(cr, w, h)`.
   - Draw with `flat.card`, then `flat.header`.
   - Use only `flat.theme` roles for colour.
   - At the end, return the table when `WING` is set. Otherwise run
     `conky_main`. Copy the pattern from `Weather/weather.lua`.
2. If the data is slow, add a feeder.
   - Write a script that prints TSV to stdout.
   - Print nothing on failure.
   - Add it to `SOURCES` in `Common/feeds.py` with an interval.
   - Read it in the widget with `flat.snapshot("<name>")`.
3. Add a section to the wing's `sections` list in `Wings/wing_left.lua`
   or `Wings/wing_right.lua`.

   ```lua
   { h = 150, update = mod.update, draw = mod.draw }
   ```

   - Use `size = fn` when the height follows the content.
   - Use `flex = true` on the card that takes spare height.
4. Restart the wing and `conky-feeds.service`, then check the card.

!!! warning "Traps"

    - **Colours only through theme roles.** Use `flat.theme.text`,
      `dim`, `faint`, `accent`, `red`, `yellow` or `green`. Do not
      write hex values in widget code.
    - **Hexes must be palette hexes.** `switch-theme.sh` recolours the
      conky Lua files. A hex that is not in the palette does not
      change with the theme and looks wrong.
    - **The draw loop must not call slow commands.** Read snapshot
      files only. No `io.popen`, no `${exec}` in the draw path, no
      network calls. A slow call blocks drawing, and `io.popen` can
      crash conky.
