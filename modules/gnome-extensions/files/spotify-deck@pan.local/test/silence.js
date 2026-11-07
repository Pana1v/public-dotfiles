import GLib from 'gi://GLib';
const EXT = '/home/pan-navigator/.local/share/gnome-shell/extensions/spotify-deck@pan.local';
const {VizEngine} = await import(`file://${EXT}/src/viz.js`);

const loop = new GLib.MainLoop(null, false);
const eng = new VizEngine(24);
const marks = [];
let peak = 0;
eng.connect('bars', (_e, bars) => { peak = Math.max(peak, ...bars); });
eng.setActive(true);

const sample = (label) => {
  marks.push(`${label.padEnd(16)} mode=${eng.mode} covering=${eng._coveringSilence} peakSinceLast=${peak.toFixed(3)}`);
  peak = 0;
};

GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2,  () => { sample('t=2s (grace)');  return GLib.SOURCE_REMOVE; });
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 8,  () => { sample('t=8s (covered)'); return GLib.SOURCE_REMOVE; });
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 10, () => {
  marks.forEach(m => print('  ' + m));
  print('\n  EXPECT: t=2s peak 0 not yet covering; t=8s covering=true with peak>0 (synth animating)');
  eng.destroy(); loop.quit(); return GLib.SOURCE_REMOVE;
});
loop.run();
