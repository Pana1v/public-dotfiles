// Clip Deck: clipboard history for text, links, colours, images and
// screenshots, opened with Super+V as a keyboard-first conky card.
// Enter pastes straight into the window you came from.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {Store} from './store.js';
import {Deck} from './deck.js';

const IMAGE_MIMES = ['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/bmp'];
const TEXT_MIMES = ['text/plain;charset=utf-8', 'UTF8_STRING', 'text/plain', 'STRING'];
// Password managers mark secrets with these; never store them.
const SECRET_MIMES = ['x-kde-passwordManagerHint', 'application/x-nautilus-secret'];
// Terminals paste with Ctrl+Shift+V.
const TERMINALS = ['terminator', 'kitty', 'org.gnome.ptyxis', 'ptyxis', 'gnome-terminal-server',
    'org.gnome.terminal', 'org.gnome.console', 'kgx', 'alacritty', 'wezterm', 'foot', 'konsole', 'tilix'];
const MAX_TEXT = 200000;

export default class ClipDeck extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._store = new Store(this._settings.get_int('history-size'));
        this._deck = new Deck(this._store, (item, paste) => this._use(item, paste));
        this._vk = Clutter.get_default_backend().get_default_seat()
            .create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
        this._pasteId = 0;

        this._ownerId = global.display.get_selection().connect('owner-changed', (_s, type) => {
            if (type === Meta.SelectionType.SELECTION_CLIPBOARD)
                this._capture();
        });

        Main.wm.addKeybinding('toggle', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW, () => this._deck.toggle());
    }

    disable() {
        Main.wm.removeKeybinding('toggle');
        global.display.get_selection().disconnect(this._ownerId);
        if (this._pasteId)
            GLib.source_remove(this._pasteId);
        this._deck.destroy();
        this._store.destroy();
        this._vk = this._deck = this._store = this._settings = null;
    }

    _capture() {
        const cb = St.Clipboard.get_default();
        const mimes = cb.get_mimetypes(St.ClipboardType.CLIPBOARD);
        if (mimes.some(m => SECRET_MIMES.includes(m)))
            return;

        const image = IMAGE_MIMES.find(m => mimes.includes(m));
        if (image) {
            cb.get_content(St.ClipboardType.CLIPBOARD, image, (_c, bytes) => {
                const max = this._settings?.get_int('max-image-mb') * 1024 * 1024;
                if (!this._store || !bytes || bytes.get_size() === 0 || bytes.get_size() > max)
                    return;
                this._store.addImage(bytes, image);
                this._deck.refresh();
            });
            return;
        }

        if (mimes.some(m => TEXT_MIMES.includes(m) || m.startsWith('text/'))) {
            cb.get_text(St.ClipboardType.CLIPBOARD, (_c, text) => {
                if (!this._store || !text || !text.trim() || text.length > MAX_TEXT)
                    return;
                this._store.addText(text);
                this._deck.refresh();
            });
        }
    }

    /** Put the clip on the clipboard; paste = also press the paste keys. */
    _use(item, paste) {
        const cb = St.Clipboard.get_default();
        if (item.kind === 'image')
            cb.set_content(St.ClipboardType.CLIPBOARD, item.mime, this._store.readImage(item));
        else
            cb.set_text(St.ClipboardType.CLIPBOARD, item.text);

        if (!paste)
            return;
        // Give focus a moment to return to the window behind the deck.
        this._pasteId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, () => {
            this._pasteId = 0;
            this._pressPaste();
            return GLib.SOURCE_REMOVE;
        });
    }

    _pressPaste() {
        const win = global.display.focus_window;
        const cls = (win?.get_wm_class() ?? '').toLowerCase();
        const shift = TERMINALS.includes(cls);
        const t = Clutter.CURRENT_TIME;
        const key = (k, down) => this._vk.notify_keyval(t, k,
            down ? Clutter.KeyState.PRESSED : Clutter.KeyState.RELEASED);
        key(Clutter.KEY_Control_L, true);
        if (shift)
            key(Clutter.KEY_Shift_L, true);
        key(Clutter.KEY_v, true);
        key(Clutter.KEY_v, false);
        if (shift)
            key(Clutter.KEY_Shift_L, false);
        key(Clutter.KEY_Control_L, false);
    }
}
