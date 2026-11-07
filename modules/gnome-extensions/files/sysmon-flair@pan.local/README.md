# System Monitor Flair

Replaces the stock GNOME `system-monitor` extension with the same readings plus
rolling history, a continuous colour ramp, temperatures, NVIDIA GPU, and a
detail dropdown.

```
┌────────────────────┐ ┌──────────────┐
│69°  ░░▒▒▓▓▒▒   34% │ │░▒▓█▓▒░   19% │
└────────────────────┘ └──────────────┘
         CPU                 GPU
```

The panel carries processor load and temperature, and graphics load, each over
a minute of history. Everything else lives one click away.

Temperature reads from the leading edge and load from the trailing edge of the
same chip: two numbers reading inward from opposite ends stay distinguishable
at a glance in a way two adjacent numbers would not.

Click for memory, swap, network, temperatures, per-core load, and what is
actually using the machine.

## What it adds over the stock extension

| | Stock | This |
|---|---|---|
| Panel | CPU, memory, swap, net, all at once | CPU load + temp, GPU load |
| History | none, a bare number | 60s sparkline on each |
| Colour | one class flips at 80% | continuous ramp, green to red |
| Detail view | none | memory, swap, net, temps, per-core, top processes |
| Labels | symbolic icons | none; position identifies the two stats |

## Design decisions worth knowing

**Sensors are resolved by name, never by index.** `hwmon` numbers are assigned
in driver probe order and change across reboots, so `/sys/class/hwmon/hwmon8`
can become the wifi card after a kernel update. Every lookup scans for a
driver named `coretemp` / `k10temp` / `zenpower` instead.

**GPU stats come from one long-lived process.** Spawning `nvidia-smi` each
second costs a process launch plus 50-100ms of work. `nvidia-smi --loop` keeps
one process streaming lines, measured at **0.12% of one core** steady state.

**Network counts physical interfaces only.** Traffic over `tailscale0` also
traverses the physical NIC, and bridges (`br-*`, `docker0`) double-count
container traffic. Summing everything inflates the reading, so overlay and
virtual interfaces are filtered out.

**Per-core arrays are sliced.** GTop sizes `xcpu_*` to a compile-time maximum
of 1024 entries regardless of your CPU. Iterating the array as given would add
a thousand phantom cores reading zero.

**The process list is not sampled on the panel tick.** Ranking processes costs
three GTop syscalls across ~600 PIDs. It only runs while the dropdown is open,
and then only every third tick.

**Network colour scale decays.** Throughput has no natural maximum, so the
scale is the fastest rate seen recently. A peak that only ever rose would let
one large transfer flatten the graph for the rest of the session.

**The panel and the dropdown have opposite constraints.** The panel is always
on screen competing for width, so only load earns a place there. The dropdown
costs nothing until opened, so everything else lives in it. All the data is
still collected either way; moving a reading between the two is a layout
change, not a data change.

**Panel digits are tabular.** Proportional figures make a value ticking
9% -> 10% -> 9% shove its neighbours back and forth. `font-feature-settings:
"tnum"` fixes every digit to the same width.

**The number sits on the graph, not beside it.** `Clutter.BinLayout` stacks its
children in one cell instead of placing them in a row, which buys the graph
about twice the width in the same footprint. The value stays a real `St.Label`
rather than Cairo text so it renders through Pango with the shell's own font;
Cairo's text API would ignore it.

**The chip states its height.** Inside a BinLayout with nothing constraining it
vertically, a `y_expand` DrawingArea takes a square allocation: a 48px-wide
graph becomes 48px tall and blows out the panel.

## Files

| File | Responsibility |
|---|---|
| `extension.js` | Wiring, tick loop, update throttling |
| `src/sources.js` | All data collection, no UI |
| `src/graph.js` | Sparkline, load bar, colour ramp |
| `src/panel.js` | Compact panel chips |
| `src/menu.js` | Detail dropdown |

## Tuning

Colour stops are `LOAD_STOPS` in `src/graph.js`. History length and sparkline
width are at the top of `src/panel.js`. Tick rate and throttles are at the top
of `extension.js`.

## Replaces

Disable the stock extension, which shows the same core stats:

```
gnome-extensions disable system-monitor@gnome-shell-extensions.gcampax.github.com
```
