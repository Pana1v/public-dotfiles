// History on disk: ~/.local/share/clip-deck/history.json plus one file per
// image under images/. Newest first; pinned entries never age out.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';

const DIR = GLib.build_filenamev([GLib.get_user_data_dir(), 'clip-deck']);
const IMG_DIR = GLib.build_filenamev([DIR, 'images']);
const DB = GLib.build_filenamev([DIR, 'history.json']);

const EXT = {'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif', 'image/bmp': 'bmp'};

/** What a text clip is, so the deck can tag, filter and preview it. */
export function classify(text) {
    const t = text.trim();
    if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t))
        return 'hex';
    if (/^[a-z][a-z0-9+.-]*:\/\/\S+$/i.test(t))
        return 'url';
    if (/^(~|\.{0,2}\/)\S*$/.test(t) || /^file:\/\//.test(t))
        return 'path';
    if (t.includes('\n'))
        return 'code';
    return 'text';
}

/** Width and height from a PNG header, null for anything else. */
function pngSize(arr) {
    if (arr.length < 24 || arr[1] !== 0x50 || arr[2] !== 0x4e || arr[3] !== 0x47)
        return null;
    const be = i => ((arr[i] << 24) >>> 0) + (arr[i + 1] << 16) + (arr[i + 2] << 8) + arr[i + 3];
    return [be(16), be(20)];
}

export class Store {
    constructor(limit = 300) {
        this.limit = limit;
        GLib.mkdir_with_parents(IMG_DIR, 0o700);
        this.items = this._load();
        this._saveId = 0;
    }

    destroy() {
        if (this._saveId) {
            GLib.source_remove(this._saveId);
            this._saveId = 0;
            this._write();
        }
    }

    _load() {
        try {
            const [, data] = GLib.file_get_contents(DB);
            const items = JSON.parse(new TextDecoder().decode(data)).items ?? [];
            // Drop images whose file went missing.
            return items.filter(i => i.kind !== 'image' || GLib.file_test(i.file, GLib.FileTest.EXISTS));
        } catch {
            return [];
        }
    }

    _write() {
        const json = JSON.stringify({version: 1, items: this.items});
        try {
            GLib.file_set_contents(DB, json);
        } catch (e) {
            console.error(`clip-deck: save failed: ${e}`);
        }
    }

    _save() {
        if (this._saveId)
            return;
        this._saveId = GLib.timeout_add(GLib.PRIORITY_LOW, 400, () => {
            this._saveId = 0;
            this._write();
            return GLib.SOURCE_REMOVE;
        });
    }

    _bump(hash) {
        const i = this.items.findIndex(x => x.hash === hash);
        if (i < 0)
            return null;
        const [item] = this.items.splice(i, 1);
        item.t = Date.now();
        this.items.unshift(item);
        this._save();
        return item;
    }

    _push(item) {
        this.items.unshift(item);
        this._trim();
        this._save();
        return item;
    }

    _trim() {
        let loose = 0;
        this.items = this.items.filter(item => {
            if (item.pinned || ++loose <= this.limit)
                return true;
            this._unlink(item);
            return false;
        });
    }

    _unlink(item) {
        if (item.kind === 'image')
            GLib.unlink(item.file);
    }

    addText(text) {
        const hash = GLib.compute_checksum_for_string(GLib.ChecksumType.SHA1, text, -1);
        return this._bump(hash) ?? this._push({
            id: hash, hash, kind: 'text', type: classify(text), text, pinned: false, t: Date.now(),
        });
    }

    addImage(bytes, mime) {
        const hash = GLib.compute_checksum_for_bytes(GLib.ChecksumType.SHA1, bytes);
        const known = this._bump(hash);
        if (known)
            return known;
        const arr = bytes.toArray();
        const file = GLib.build_filenamev([IMG_DIR, `${hash}.${EXT[mime] ?? 'img'}`]);
        GLib.file_set_contents(file, arr);
        const size = pngSize(arr);
        return this._push({
            id: hash, hash, kind: 'image', type: 'image', mime, file,
            w: size?.[0] ?? 0, h: size?.[1] ?? 0, bytes: arr.length,
            pinned: false, t: Date.now(),
        });
    }

    readImage(item) {
        const [, data] = GLib.file_get_contents(item.file);
        return new GLib.Bytes(data);
    }

    togglePin(item) {
        item.pinned = !item.pinned;
        if (!item.pinned)
            this._trim();
        this._save();
    }

    remove(item) {
        this.items = this.items.filter(x => x !== item);
        this._unlink(item);
        this._save();
    }

    clearLoose() {
        for (const item of this.items.filter(x => !x.pinned))
            this._unlink(item);
        this.items = this.items.filter(x => x.pinned);
        this._save();
    }

    static uri(path) {
        return Gio.File.new_for_path(path).get_uri();
    }
}
