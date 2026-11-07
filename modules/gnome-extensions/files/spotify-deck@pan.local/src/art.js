import GdkPixbuf from 'gi://GdkPixbuf';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Soup from 'gi://Soup?version=3.0';

const CACHE_SUBDIR = 'spotify-deck';
const MAX_CACHE_FILES = 60;

// Dominant colour is sampled from a tiny thumbnail: 32x32 is plenty to find
// the cover's character and keeps the per-track cost negligible.
const SAMPLE_SIZE = 32;

const RGB_MAX = 255;

/**
 * Fetches remote album art, caches it on disk, and derives an accent colour.
 *
 * St widgets cannot load an https:// URI directly, so every cover has to land
 * on disk before it can be shown. We then point CSS background-image at the
 * cached file rather than pushing pixels through Clutter content, because St
 * styling has been stable far longer than the Clutter image APIs.
 */
export const ArtCache = GObject.registerClass({
    Signals: {
        'ready': {param_types: [GObject.TYPE_STRING, GObject.TYPE_JSOBJECT]},
    },
}, class ArtCache extends GObject.Object {
    constructor() {
        super();

        this._session = new Soup.Session({timeout: 15});
        this._cancellable = new Gio.Cancellable();
        this._accents = new Map();   // url -> {r,g,b}
        this._paths = new Map();     // url -> local path
        this._inFlight = new Set();

        this._dir = Gio.File.new_for_path(
            GLib.build_filenamev([GLib.get_user_cache_dir(), CACHE_SUBDIR]));

        try {
            this._dir.make_directory_with_parents(null);
        } catch (e) {
            if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.EXISTS))
                logError(e, 'spotify-deck: cache dir');
        }
    }

    pathFor(url) {
        return this._paths.get(url) ?? null;
    }

    accentFor(url) {
        return this._accents.get(url) ?? null;
    }

    _cacheFile(url) {
        // Content-addressed by URL so the same cover is fetched once ever.
        const key = GLib.compute_checksum_for_string(
            GLib.ChecksumType.SHA256, url, -1);
        return this._dir.get_child(`${key}.img`);
    }

    /**
     * Ensures the cover for url is on disk, then emits 'ready' with its path
     * and accent colour. Re-requesting a cached url emits immediately.
     */
    request(url) {
        if (!url)
            return;

        if (this._paths.has(url)) {
            this.emit('ready', url, {
                path: this._paths.get(url),
                accent: this._accents.get(url),
            });
            return;
        }

        if (this._inFlight.has(url))
            return;

        const file = this._cacheFile(url);

        if (file.query_exists(null)) {
            this._finish(url, file.get_path());
            return;
        }

        // Some players hand back a local file:// path already.
        if (url.startsWith('file://')) {
            this._finish(url, Gio.File.new_for_uri(url).get_path());
            return;
        }

        this._inFlight.add(url);
        this._download(url, file);
    }

    _download(url, file) {
        let message;
        try {
            message = Soup.Message.new('GET', url);
        } catch (e) {
            this._inFlight.delete(url);
            return;
        }

        this._session.send_and_read_async(
            message, GLib.PRIORITY_DEFAULT, this._cancellable,
            (session, res) => {
                this._inFlight.delete(url);

                let bytes;
                try {
                    bytes = session.send_and_read_finish(res);
                } catch (e) {
                    if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        logError(e, 'spotify-deck: art download');
                    return;
                }

                if (message.get_status() !== Soup.Status.OK || !bytes)
                    return;

                try {
                    file.replace_contents(
                        bytes.get_data(), null, false,
                        Gio.FileCreateFlags.REPLACE_DESTINATION, null);
                } catch (e) {
                    logError(e, 'spotify-deck: art write');
                    return;
                }

                this._finish(url, file.get_path());
                this._prune();
            });
    }

    _finish(url, path) {
        this._paths.set(url, path);

        const accent = this._extractAccent(path);
        if (accent)
            this._accents.set(url, accent);

        this.emit('ready', url, {path, accent});
    }

    /**
     * Picks the colour a person would call "the" colour of the cover.
     *
     * A plain pixel mean returns mud, because opposing hues cancel. Weighting
     * each pixel by saturation squared times value biases hard toward the few
     * vivid pixels that actually define the artwork's character.
     */
    _extractAccent(path) {
        let pixbuf;
        try {
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                path, SAMPLE_SIZE, SAMPLE_SIZE, true);
        } catch (e) {
            return null;
        }

        const pixels = pixbuf.get_pixels();
        const channels = pixbuf.get_n_channels();
        const rowstride = pixbuf.get_rowstride();
        const width = pixbuf.get_width();
        const height = pixbuf.get_height();

        let wr = 0, wg = 0, wb = 0, wsum = 0;

        for (let y = 0; y < height; y++) {
            for (let x = 0; x < width; x++) {
                const o = y * rowstride + x * channels;
                const r = pixels[o] / RGB_MAX;
                const g = pixels[o + 1] / RGB_MAX;
                const b = pixels[o + 2] / RGB_MAX;

                const max = Math.max(r, g, b);
                const min = Math.min(r, g, b);
                const sat = max === 0 ? 0 : (max - min) / max;

                // Squaring saturation makes vivid pixels dominate decisively.
                const weight = sat * sat * max;

                wr += r * weight;
                wg += g * weight;
                wb += b * weight;
                wsum += weight;
            }
        }

        // A fully desaturated cover (black and white art) has no accent to
        // find; the caller falls back to a neutral theme colour.
        if (wsum < 0.001)
            return null;

        return this._normaliseForUi(wr / wsum, wg / wsum, wb / wsum);
    }

    /**
     * Lifts the accent into a band that stays legible on a dark panel: very
     * dark covers would otherwise produce an invisible bar colour.
     */
    _normaliseForUi(r, g, b) {
        const max = Math.max(r, g, b);
        const MIN_BRIGHTNESS = 0.62;

        let scale = 1;
        if (max > 0 && max < MIN_BRIGHTNESS)
            scale = MIN_BRIGHTNESS / max;

        const clamp = v => Math.round(Math.max(0, Math.min(1, v * scale)) * RGB_MAX);

        return {r: clamp(r), g: clamp(g), b: clamp(b)};
    }

    /** Keeps the cache from growing without bound across listening sessions. */
    _prune() {
        let entries;
        try {
            const enumerator = this._dir.enumerate_children(
                'standard::name,time::modified',
                Gio.FileQueryInfoFlags.NONE, null);

            entries = [];
            let info;
            while ((info = enumerator.next_file(null)) !== null) {
                entries.push({
                    name: info.get_name(),
                    mtime: info.get_modification_date_time()?.to_unix() ?? 0,
                });
            }
            enumerator.close(null);
        } catch (e) {
            return;
        }

        if (entries.length <= MAX_CACHE_FILES)
            return;

        entries.sort((a, b) => a.mtime - b.mtime)
            .slice(0, entries.length - MAX_CACHE_FILES)
            .forEach(entry => {
                try {
                    this._dir.get_child(entry.name).delete(null);
                } catch (e) {
                    // Another shell instance may have removed it already.
                }
            });
    }

    destroy() {
        this._cancellable.cancel();
        this._session.abort();
        this._paths.clear();
        this._accents.clear();
        this._inFlight.clear();
    }
});
