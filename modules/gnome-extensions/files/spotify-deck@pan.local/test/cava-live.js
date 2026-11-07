import GLib from 'gi://GLib';
const EXT = '/home/pan-navigator/.local/share/gnome-shell/extensions/spotify-deck@pan.local';
const {VizEngine, VizMode} = await import(`file://${EXT}/src/viz.js`);

const loop = new GLib.MainLoop(null, false);
const eng = new VizEngine(24);
let frames = 0, peak = 0, nonzero = 0, lastBars = null;

eng.connect('bars', (_e, bars) => {
  frames++;
  const m = Math.max(...bars);
  peak = Math.max(peak, m);
  if (m > 0.02) nonzero++;
  lastBars = bars;
});

eng.setActive(true);

GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 6, () => {
  print('mode          : ' + eng.mode + (eng.hasRealAudio ? '  (REAL SPECTRUM)' : '  (fallback)'));
  print('frames        : ' + frames);
  print('peak bar      : ' + peak.toFixed(3));
  print('frames >2%    : ' + nonzero);
  if (lastBars)
    print('last frame    : ' + lastBars.map(v => '▁▂▃▄▅▆▇█'[Math.min(7, Math.floor(v*8))]).join(''));
  eng.destroy();
  loop.quit();
  return GLib.SOURCE_REMOVE;
});
loop.run();
