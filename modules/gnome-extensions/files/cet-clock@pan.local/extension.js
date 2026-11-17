import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Panel centre, right of the date:   Wed 11 Nov 12:47   CET 08:17
// The zone name follows summer time by itself (CET / CEST).
const ZONE = 'Europe/Berlin';
const REFRESH_SECONDS = 15;

export default class CetClockExtension extends Extension {
    enable() {
        this._zone = GLib.TimeZone.new_identifier(ZONE);
        this._label = new St.Label({
            style_class: 'cet-clock',
            y_align: Clutter.ActorAlign.CENTER,
        });
        Main.panel._centerBox.add_child(this._label);

        this._sync();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, REFRESH_SECONDS, () => {
            this._sync();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        GLib.source_remove(this._timer);
        this._timer = null;

        this._label.destroy();
        this._label = null;
        this._zone = null;
    }

    _sync() {
        this._label.text = GLib.DateTime.new_now(this._zone).format('%Z %H:%M');
    }
}
