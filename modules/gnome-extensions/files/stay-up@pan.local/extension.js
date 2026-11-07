import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export default class StayUpExtension extends Extension {
    enable() {
        // getSettings() reads the compiled schema declared in metadata.json.
        this._settings = this.getSettings();

        // Register the global hotkey. The action name must match the key in the
        // gschema. addKeybinding wires the GSettings 'as' key to our callback and
        // owns the grab for as long as the extension is enabled.
        Main.wm.addKeybinding(
            'toggle-above',
            this._settings,
            Meta.KeyBindingFlags.NONE,
            // NORMAL = on the desktop; OVERVIEW so it also works in the activities view.
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW,
            () => this._toggleAbove()
        );
    }

    _toggleAbove() {
        // The window the user is actually looking at. null when focus is on a
        // panel/overview element rather than a real window — nothing to do then.
        const win = global.display.focus_window;
        if (!win)
            return;

        // is_above() reflects the _NET_WM_STATE_ABOVE flag mutter tracks per window.
        // This is the same state the titlebar 'Always on Top' toggles — we just reach
        // it directly, so CSD apps (Spotify, GNOME apps) work too.
        if (win.is_above())
            win.unmake_above();
        else
            win.make_above();
    }

    disable() {
        // Must release the keybinding here: extensions are disabled on lock screen,
        // and a leaked grab would persist or error on re-enable.
        Main.wm.removeKeybinding('toggle-above');
        this._settings = null;
    }
}
