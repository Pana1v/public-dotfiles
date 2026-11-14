// Show Desktop: a real minimise-all toggle for the show-desktop shortcut.
//
// mutter's own show-desktop only hides windows and keeps a "showing desktop"
// state. Restoring from there (dock click, alt-tab, pop-shell stacks) can
// leave windows shown but stacked under the conky widgets, which are
// desktop-type windows. Minimising never enters that state.
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const BINDING = 'show-desktop';

export default class ShowDesktop extends Extension {
    enable() {
        // workspace -> windows we minimised, most recently used first
        this._saved = new Map();
        Main.wm.setCustomKeybindingHandler(BINDING,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW,
            () => this._toggle());
    }

    disable() {
        Meta.keybindings_set_custom_handler(BINDING, null);
        this._saved = null;
    }

    _windows(ws) {
        return global.display.get_tab_list(Meta.TabList.NORMAL_ALL, ws)
            .filter(w => !w.skip_taskbar && w.get_window_type() === Meta.WindowType.NORMAL);
    }

    _toggle() {
        if (Main.overview.visible)
            Main.overview.hide();
        const ws = global.workspace_manager.get_active_workspace();
        const time = global.get_current_time();
        const visible = this._windows(ws).filter(w => !w.minimized);

        if (visible.length > 0) {
            for (const w of visible)
                w.minimize();
            this._saved.set(ws, visible);
            return;
        }

        // Nothing showing: bring back what we hid, oldest first so the
        // stacking order ends up as it was, then focus the last used one.
        const saved = (this._saved.get(ws) ?? []).filter(w => w.get_workspace?.() && w.minimized);
        this._saved.delete(ws);
        for (const w of [...saved].reverse())
            w.unminimize();
        if (saved.length > 0)
            saved[0].activate(time);
    }
}
