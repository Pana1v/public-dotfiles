import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GdkPixbuf from 'gi://GdkPixbuf';
import * as log from './log.js';
const THUMB_MAX_SIZE = 256;
const THUMB_SUFFIX = '.thumb.png';
let _activeImagesDir = '';
export function imageNameFor(id) {
    return `${id}.png`;
}
export function imagePathFor(imageName) {
    return GLib.build_filenamev([_activeImagesDir, imageName]);
}
export function thumbnailPathFor(imageName) {
    return imagePathFor(imageName).replace(/\.png$/i, THUMB_SUFFIX);
}
export class Store {
    _path = '';
    _imagesDir = '';
    constructor(dir) {
        const ret = GLib.mkdir_with_parents(dir, parseInt('0700', 8));
        if (ret === 0) {
            this._path = GLib.build_filenamev([dir, 'history.json']);
            this._imagesDir = GLib.build_filenamev([dir, 'images']);
            _activeImagesDir = this._imagesDir;
            GLib.mkdir_with_parents(this._imagesDir, parseInt('0700', 8));
            log.info(`store location set to ${this._path}`);
        }
        else {
            log.error(`unable to create store directory: ${dir}`);
        }
    }
    async load() {
        log.info(`loading history async from ${this._path}`);
        try {
            const file = Gio.file_new_for_path(this._path);
            if (!file.query_exists(null)) {
                return [];
            }
            const result = await new Promise((resolve, reject) => {
                file.load_contents_async(null, (file, res) => {
                    try {
                        resolve(file.load_contents_finish(res));
                    }
                    catch (e) {
                        reject(e);
                    }
                });
            });
            const contents = Array.isArray(result)
                ? result.find((v) => v instanceof Uint8Array)
                : result;
            if (!contents) {
                return [];
            }
            let text = this._safeDecode(contents);
            if (text && text.trim().length > 0) {
                text = text.replace(/^\uFEFF/, '').trim();
                try {
                    return JSON.parse(text);
                }
                catch (e) {
                    log.error(`JSON parse failed for ${this._path}: ${e}`);
                    return [];
                }
            }
        }
        catch (err) {
            log.error(`load history failed: ${err}`);
        }
        return [];
    }
    _safeDecode(data) {
        if (!data)
            return '';
        try {
            const ui8 = data instanceof Uint8Array ? data : new Uint8Array(data);
            return new TextDecoder().decode(ui8);
        }
        catch (e) {
            log.warn(`TextDecoder failed, using byte fallback: ${e}`);
            let text = '';
            let bytes = data;
            if (data && typeof data.get_data === 'function') {
                bytes = data.get_data();
            }
            if (bytes && bytes.length) {
                for (let i = 0; i < bytes.length; i++) {
                    text += String.fromCharCode(bytes[i]);
                }
            }
            return text;
        }
    }
    async save(history) {
        try {
            const json = JSON.stringify(history);
            const bytes = GLib.Bytes.new(new TextEncoder().encode(json));
            await this._replaceContents(this._path, bytes);
        }
        catch (err) {
            log.error(`save history failed: ${err}`);
        }
    }
    async _replaceContents(path, bytes) {
        const file = Gio.file_new_for_path(path);
        await new Promise((resolve, reject) => {
            file.replace_contents_async(bytes, null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null, (file, res) => {
                try {
                    file.replace_contents_finish(res);
                    resolve();
                }
                catch (e) {
                    reject(e);
                }
            });
        });
    }
    async saveImage(id, bytes) {
        const imageName = imageNameFor(id);
        try {
            await this._replaceContents(imagePathFor(imageName), bytes);
            try {
                await this._writeThumbnail(bytes, thumbnailPathFor(imageName));
            }
            catch (err) {
                log.warn(`failed to create thumbnail for ${imageName}: ${err}`);
            }
            return imageName;
        }
        catch (err) {
            log.error(`failed to save image: ${err}`);
            return null;
        }
    }
    async _writeThumbnail(bytes, thumbPath) {
        const stream = Gio.MemoryInputStream.new_from_bytes(bytes);
        const pixbuf = await new Promise((resolve, reject) => {
            GdkPixbuf.Pixbuf.new_from_stream_at_scale_async(stream, THUMB_MAX_SIZE, THUMB_MAX_SIZE, true, null, (_stream, res) => {
                try {
                    resolve(GdkPixbuf.Pixbuf.new_from_stream_finish(res));
                }
                catch (e) {
                    reject(e);
                }
            });
        });
        pixbuf.savev(thumbPath, 'png', ['compression'], ['9']);
    }
    deleteImage(imageName) {
        const path = imagePathFor(imageName);
        if (GLib.path_get_dirname(path) !== this._imagesDir) {
            log.warn(`refusing to delete image outside ${this._imagesDir}: ${path}`);
            return;
        }
        this._deleteFile(path);
        this._deleteFile(thumbnailPathFor(imageName));
    }
    clearAll() {
        this._deleteRecursive(this._imagesDir);
        this._deleteFile(this._path);
        GLib.mkdir_with_parents(this._imagesDir, parseInt('0700', 8));
    }
    _deleteRecursive(path) {
        let file;
        try {
            file = Gio.file_new_for_path(path);
            if (!file.query_exists(null)) {
                return;
            }
            const info = file.query_info('standard::type', Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            if (info.get_file_type() !== Gio.FileType.DIRECTORY) {
                file.delete(null);
                return;
            }
            const enumerator = file.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            try {
                let child;
                while ((child = enumerator.next_file(null)) !== null) {
                    this._deleteRecursive(GLib.build_filenamev([path, child.get_name()]));
                }
            }
            finally {
                enumerator.close(null);
            }
            file.delete(null);
        }
        catch (err) {
            if (err?.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND)) {
                return;
            }
            log.warn(`failed to delete ${path}: ${err}`);
        }
    }
    _deleteFile(path) {
        try {
            const file = Gio.file_new_for_path(path);
            if (file.query_exists(null)) {
                file.delete(null);
            }
        }
        catch (err) {
            if (err?.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND)) {
                return;
            }
            log.warn(`failed to delete ${path}: ${err}`);
        }
    }
}
