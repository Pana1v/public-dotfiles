# Tests

These run outside GNOME Shell. The modules under `src/` deliberately import only
Gio/GLib/Soup/GdkPixbuf, never St or Clutter, which is what makes that possible.

```
gjs -m test/frames.js     # cava frame parsing, synthetic bytes, no cava needed
gjs -m test/live.js       # MPRIS + art fetch + viz against the real session bus
./test/syntax.sh extension.js src/*.js
```

`frames.js` covers the parts that only run when cava is installed: 16-bit
little-endian decoding, newest-frame-wins when several arrive in one read, and
partial-frame reassembly across reads.

Drawing code (`src/strip.js`) needs a shell. Wayland cannot restart the shell in
place, so use a nested one:

```
MUTTER_DEBUG_DUMMY_MODE_SPECS=1600x900 \
  dbus-run-session -- gnome-shell --nested --wayland
```

Note that a nested shell gets a *fresh session bus*, so Spotify's MPRIS name
does not exist inside it and the strip stays hidden. To exercise the drawing,
temporarily force the indicator visible in `_sync()`.
