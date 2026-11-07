import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import * as log from './log.js';
export function log_methods(obj) {
    var result = [];
    for (var id in obj) {
        try {
            if (typeof (obj[id]) == "function") {
                result.push(id + ": " + obj[id].toString());
            }
        }
        catch (err) {
            result.push(id + ": inaccessible");
        }
    }
    log.info(result.toString());
}
export function log_object(obj) {
    let seen = [];
    let json = JSON.stringify(obj, function (_key, val) {
        if (val != null && typeof val == "object") {
            if (seen.indexOf(val) >= 0) {
                return;
            }
            seen.push(val);
        }
        return val;
    });
    log.info(json);
}
export function hashCode(text) {
    var hash = 0;
    if (text.length == 0)
        return hash;
    for (let i = 0; i < text.length; i++) {
        let char = text.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
    }
    return hash;
}
export function hashBytes(bytes) {
    if (!bytes)
        return 0;
    let checksum = GLib.compute_checksum_for_data(GLib.ChecksumType.MD5, bytes.get_data());
    return hashCode(checksum);
}
export function truncate(text, length) {
    text = text.trim();
    text = text.replace(/\s+/g, ' ');
    if (text.length > length) {
        text = text.substring(0, length - 1) + '...';
    }
    return text;
}
export function spawnAsync(...args) {
    try {
        let flags = GLib.SpawnFlags.SEARCH_PATH;
        GLib.spawn_async(null, args, null, flags, null);
    }
    catch (err) {
        log.error(`an exception occurred: ${err}`);
    }
}
export async function spawnSync(...args) {
    try {
        let proc = new Gio.Subprocess({
            argv: args,
            flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
        });
        proc.init(null);
        return new Promise((resolve, reject) => {
            proc.communicate_utf8_async(null, null, (proc, res) => {
                try {
                    let [_stdout, stderr] = proc.communicate_utf8_finish(res);
                    if (stderr && stderr.length > 0) {
                        log.error(`an error occurred: ${stderr}`);
                        resolve(false);
                    }
                    else {
                        resolve(true);
                    }
                }
                catch (err) {
                    log.error(`an exception occurred: ${err}`);
                    reject(err);
                }
            });
        });
    }
    catch (err) {
        log.error(`an exception occurred: ${err}`);
        return false;
    }
}
