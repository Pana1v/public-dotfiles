import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import GLib from 'gi://GLib';
import GdkPixbuf from 'gi://GdkPixbuf';
import { ClipboardItem, ClipboardItemType } from './clipboardItem.js';
import { imageNameFor, imagePathFor, thumbnailPathFor } from './store.js';
import * as log from './log.js';
let _ = (s) => s;
export function init(gettextFunc) {
    _ = gettextFunc;
}
const PREVIEW_MAX_WIDTH = 128;
const PREVIEW_MAX_HEIGHT = 64;
const PREVIEW_MAX_ASPECT = 4;
const _sizeCache = new Map();
export class ClipboardItemImage extends ClipboardItem {
    type = ClipboardItemType.IMAGE;
    constructor(id) {
        super(id);
    }
    imageName() {
        return imageNameFor(this.id);
    }
    filePath() {
        return imagePathFor(this.imageName());
    }
    notification() {
        return _('[Image]');
    }
    displayWidget() {
        return this._buildThumbnail();
    }
    searchText() {
        return '';
    }
    async copyToClipboard() {
        try {
            const file = Gio.File.new_for_path(this.filePath());
            const bytes = await new Promise((resolve, reject) => {
                file.load_bytes_async(null, (file, res) => {
                    try {
                        const [contents] = file.load_bytes_finish(res);
                        resolve(contents);
                    }
                    catch (e) {
                        reject(e);
                    }
                });
            });
            const source = Meta.SelectionSourceMemory.new('image/png', bytes);
            global.display
                .get_selection()
                .set_owner(Meta.SelectionType.SELECTION_CLIPBOARD, source);
        }
        catch (err) {
            log.error(`failed to copy image ${this.id}: ${err}`);
        }
    }
    dispose(store) {
        store.deleteImage(this.imageName());
    }
    toJSON() {
        return {
            type: this.type,
            id: this.id,
            pinned: this.pinned,
            copiedAt: this.copiedAt,
            usage: this.usage,
            usedAt: this.usedAt,
        };
    }
    static fromJSON(raw) {
        const item = new ClipboardItemImage(raw.id);
        item.pinned = raw.pinned;
        item.copiedAt = raw.copiedAt;
        item.usage = raw.usage;
        item.usedAt = raw.usedAt;
        return item;
    }
    _previewSource() {
        const source = this.filePath();
        const thumbPath = thumbnailPathFor(this.imageName());
        try {
            if (Gio.File.new_for_path(thumbPath).query_exists(null)) {
                return thumbPath;
            }
        }
        catch {
        }
        return source;
    }
    static _measurePreview(path) {
        try {
            const [, width, height] = GdkPixbuf.Pixbuf.get_file_info(path);
            if (!width || !height) {
                return null;
            }
            const scale = Math.min(PREVIEW_MAX_WIDTH / width, PREVIEW_MAX_HEIGHT / height, 1);
            let w = Math.max(1, Math.round(width * scale));
            let h = Math.max(1, Math.round(height * scale));
            const aspect = width / height;
            if (aspect > PREVIEW_MAX_ASPECT) {
                h = Math.max(h, Math.round(w / PREVIEW_MAX_ASPECT));
            }
            else if (aspect < 1 / PREVIEW_MAX_ASPECT) {
                w = Math.max(w, Math.round(h * PREVIEW_MAX_ASPECT));
            }
            return { width: Math.max(1, w), height: Math.max(1, h) };
        }
        catch {
            return null;
        }
    }
    _buildThumbnail() {
        const original = this.filePath();
        let source = this._previewSource();
        let size = this._cachedPreviewSize(source);
        if (!size && source !== original) {
            source = original;
            size = this._cachedPreviewSize(source);
        }
        if (!size) {
            return this._placeholder();
        }
        let uri;
        try {
            uri = GLib.filename_to_uri(source, null);
        }
        catch {
            return this._placeholder();
        }
        const thumb = new St.Widget({
            style_class: 'clipboard-image-preview',
            style: `background-image: url("${uri}"); min-width: ${size.width}px; min-height: ${size.height}px; max-width: ${size.width}px; max-height: ${size.height}px;`,
            x_align: Clutter.ActorAlign.START,
            y_align: Clutter.ActorAlign.START,
            x_expand: false,
            y_expand: false,
        });
        thumb.set_size(size.width, size.height);
        return thumb;
    }
    _cachedPreviewSize(source) {
        let size = _sizeCache.get(source);
        if (size === undefined) {
            size = ClipboardItemImage._measurePreview(source);
            _sizeCache.set(source, size);
        }
        return size;
    }
    _placeholder() {
        return new St.Icon({
            icon_name: 'image-x-generic-symbolic',
            icon_size: 32,
            style_class: 'clipboard-image-placeholder',
            x_align: Clutter.ActorAlign.START,
        });
    }
}
ClipboardItem.registerType(ClipboardItemType.IMAGE, ClipboardItemImage.fromJSON);
