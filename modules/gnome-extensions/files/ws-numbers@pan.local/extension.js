import Clutter from 'gi://Clutter';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Top-left of the panel:  1 [2] 3   ([2] = active, styled by the shell theme)
// The Activities button is hidden, not removed; Super still opens the overview.
export default class WsNumbersExtension extends Extension {
    enable() {
        this._activities = Main.panel.statusArea.activities.container;
        this._activities.hide();

        this._box = new St.BoxLayout({
            style_class: 'ws-numbers',
            y_align: Clutter.ActorAlign.CENTER,
        });
        const leftBox = Main.panel._leftBox;
        leftBox.insert_child_above(this._box, this._activities);

        const wm = global.workspace_manager;
        this._signals = [
            wm.connect('notify::n-workspaces', () => this._rebuild()),
            wm.connect('active-workspace-changed', () => this._sync()),
        ];
        this._rebuild();
    }

    disable() {
        const wm = global.workspace_manager;
        this._signals.forEach(id => wm.disconnect(id));
        this._signals = null;

        this._box.destroy();
        this._box = null;

        this._activities.show();
        this._activities = null;
    }

    _rebuild() {
        const wm = global.workspace_manager;
        this._box.destroy_all_children();

        for (let i = 0; i < wm.n_workspaces; i++) {
            const button = new St.Button({label: `${i + 1}`, style_class: 'ws-number'});
            button.connect('clicked', () => {
                wm.get_workspace_by_index(i)?.activate(global.get_current_time());
            });
            this._box.add_child(button);
        }

        this._sync();
    }

    _sync() {
        const active = global.workspace_manager.get_active_workspace_index();
        this._box.get_children().forEach((button, i) => {
            button.checked = i === active;
        });
    }
}
