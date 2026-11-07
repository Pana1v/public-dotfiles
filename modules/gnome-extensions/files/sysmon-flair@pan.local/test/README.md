# Tests

`src/sources.js` imports no St or Clutter, so all data collection runs headless:

```
gjs -m test/sources.js        # CPU/mem/net/temp/GPU/processes, prints real values
./test/syntax.sh extension.js src/*.js
```

`sources.js` is the regression guard for three traps that produce silently wrong
values rather than errors:

- per-core arrays sized 1024 by GTop, not by your core count
- `proc_state.cmd` arriving as NUL-padded bytes rather than a string
- overlay interfaces (tailscale, bridges) double-counting physical traffic

Drawing needs a nested shell, as above.
