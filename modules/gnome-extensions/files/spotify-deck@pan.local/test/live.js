// Exercises the non-UI modules against the real session bus.
import GLib from 'gi://GLib';

const EXT = '/home/pan-navigator/.local/share/gnome-shell/extensions/spotify-deck@pan.local';

const {MprisWatcher} = await import(`file://${EXT}/src/mpris.js`);
const {ArtCache} = await import(`file://${EXT}/src/art.js`);
const {VizEngine} = await import(`file://${EXT}/src/viz.js`);

const loop = new GLib.MainLoop(null, false);
const results = [];
const note = (k, v) => { results.push(`${k}: ${v}`); print(`  ${k}: ${v}`); };

print('--- MPRIS ---');
const watcher = new MprisWatcher('org.mpris.MediaPlayer2.spotify');

print('--- VIZ (no cava -> expect synth) ---');
const viz = new VizEngine(28);
let vizFrames = 0;
let vizMax = 0;
viz.connect('bars', (_e, bars) => {
    vizFrames++;
    vizMax = Math.max(vizMax, ...bars);
});
viz.setActive(true);

print('--- ART ---');
const art = new ArtCache();
let artDone = false;
art.connect('ready', (_c, url, res) => {
    artDone = true;
    note('art path', res.path);
    note('art exists', GLib.file_test(res.path, GLib.FileTest.EXISTS));
    note('accent', res.accent ? `rgb(${res.accent.r},${res.accent.g},${res.accent.b})` : 'none (greyscale cover)');
});

// Give async D-Bus + HTTP time to land.
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
    const p = watcher.active;
    note('active player', p ? p._busName : 'NONE');
    if (p) {
        note('status', p.status);
        note('title', p.title);
        note('artist', p.artist);
        note('album', p.album);
        note('artUrl', p.artUrl ? p.artUrl.slice(0, 48) + '...' : 'none');
        note('lengthSec', p.lengthSec.toFixed(1));
        note('positionSec', p.positionSec.toFixed(1));
        note('canGoNext', p.canGoNext);
        if (p.artUrl) art.request(p.artUrl);
    }
    return GLib.SOURCE_REMOVE;
});

GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 6, () => {
    const p = watcher.active;
    print('--- after 4s ---');
    note('viz mode', viz.mode);
    note('viz frames', vizFrames);
    note('viz peak', vizMax.toFixed(3));
    if (p) note('position advanced to', p.positionSec.toFixed(1));
    note('art callback fired', artDone);

    viz.destroy(); art.destroy(); watcher.destroy();
    loop.quit();
    return GLib.SOURCE_REMOVE;
});

loop.run();
print('--- done ---');
