import Clutter from 'gi://Clutter';
import Pango from 'gi://Pango';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Top-left of the panel, numbered like the conky cards:  * 01  02  03
//   active    red dot + bright number
//   occupied  dim number
//   empty     hidden (the active one always shows, so the trailing
//             empty workspace appears only while you are on it)
// Click a number to go there, click the active one for the overview,
// scroll over the strip to step through workspaces.
// The Activities button is hidden, not removed; Super still opens the overview.
export default class WsNumbersExtension extends Extension {
    enable() {
        this._activities = Main.panel.statusArea.activities.container;
        this._activities.hide();

        this._box = new St.BoxLayout({
            style_class: 'ws-numbers',
            reactive: true,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._box.connect('scroll-event', (_a, event) => this._scroll(event));
        Main.panel._leftBox.insert_child_above(this._box, this._activities);

        const wm = global.workspace_manager;
        this._wsSignals = [];
        this._signals = [
            [wm, wm.connect('notify::n-workspaces', () => this._rebuild())],
            [wm, wm.connect('workspaces-reordered', () => this._rebuild())],
            [wm, wm.connect('active-workspace-changed', () => this._sync())],
        ];
        this._rebuild();
    }

    disable() {
        for (const [obj, id] of [...this._signals, ...this._wsSignals])
            obj.disconnect(id);
        this._signals = this._wsSignals = null;

        this._box.destroy();
        this._box = null;

        this._activities.show();
        this._activities = null;
    }

    _rebuild() {
        const wm = global.workspace_manager;
        for (const [obj, id] of this._wsSignals)
            obj.disconnect(id);
        this._wsSignals = [];
        this._box.destroy_all_children();

        for (let i = 0; i < wm.n_workspaces; i++) {
            const ws = wm.get_workspace_by_index(i);
            this._wsSignals.push(
                [ws, ws.connect('window-added', () => this._sync())],
                [ws, ws.connect('window-removed', () => this._sync())]);

            // Conky-card numbering: a red "lit" dot, then 01, 02 ...
            const content = new St.BoxLayout({style_class: 'ws-number-box'});
            content.add_child(new St.Widget({
                style_class: 'ws-dot',
                y_align: Clutter.ActorAlign.CENTER,
            }));
            const label = new St.Label({
                text: String(i + 1).padStart(2, '0'),
                style_class: 'ws-label',
                y_align: Clutter.ActorAlign.CENTER,
            });
            label.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
            content.add_child(label);

            const button = new St.Button({
                child: content,
                style_class: 'ws-number',
                accessible_name: `Workspace ${i + 1}`,
                y_align: Clutter.ActorAlign.CENTER,
            });
            button.connect('clicked', () => this._activate(i));
            this._box.add_child(button);
        }

        this._sync();
    }

    _occupied(ws) {
        return ws.list_windows().some(w =>
            !w.skip_taskbar && !w.is_on_all_workspaces());
    }

    _sync() {
        const wm = global.workspace_manager;
        const active = wm.get_active_workspace_index();
        this._box.get_children().forEach((button, i) => {
            const ws = wm.get_workspace_by_index(i);
            const occupied = ws ? this._occupied(ws) : false;
            button.checked = i === active;
            button.visible = i === active || occupied;
        });
    }

    _activate(i) {
        const wm = global.workspace_manager;
        if (i === wm.get_active_workspace_index()) {
            Main.overview.toggle();
            return;
        }
        wm.get_workspace_by_index(i)?.activate(global.get_current_time());
    }

    _scroll(event) {
        const dir = event.get_scroll_direction();
        let step = 0;
        if (dir === Clutter.ScrollDirection.UP || dir === Clutter.ScrollDirection.LEFT)
            step = -1;
        else if (dir === Clutter.ScrollDirection.DOWN || dir === Clutter.ScrollDirection.RIGHT)
            step = 1;
        if (!step)
            return Clutter.EVENT_PROPAGATE;

        const wm = global.workspace_manager;
        const next = wm.get_active_workspace_index() + step;
        if (next >= 0 && next < wm.n_workspaces)
            wm.get_workspace_by_index(next).activate(global.get_current_time());
        return Clutter.EVENT_STOP;
    }
}
