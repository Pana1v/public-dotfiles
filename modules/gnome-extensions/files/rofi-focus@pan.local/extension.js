import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const ROFI_WM_CLASS = 'Rofi';
const FALLBACK_ICON = 'application-x-executable';

// Rofi's own window mode reads the X11 client list, so under Wayland it only
// sees XWayland windows. The rofi windows script asks the shell instead:
//   gdbus call --session --dest org.gnome.Shell \
//     --object-path /org/gnome/Shell/Extensions/RofiFocus \
//     --method org.gnome.Shell.Extensions.RofiFocus.ListWindows
const IFACE = `
<node>
  <interface name="org.gnome.Shell.Extensions.RofiFocus">
    <method name="ListWindows">
      <arg type="a(tsssi)" direction="out" name="windows"/>
    </method>
    <method name="Activate">
      <arg type="t" direction="in" name="id"/>
    </method>
  </interface>
</node>`;
const OBJECT_PATH = '/org/gnome/Shell/Extensions/RofiFocus';

export default class RofiFocusExtension extends Extension {
    enable() {
        this._rofi = null;
        this._rofiHadFocus = false;

        this._createdId = global.display.connect('window-created', (_display, win) => {
            // Defer to idle: the window is not yet mapped when the signal fires,
            // and activating before the map is ignored.
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                if (win.get_wm_class() === ROFI_WM_CLASS)
                    this._trackRofi(win);
                return GLib.SOURCE_REMOVE;
            });
        });

        // Rofi runs as a normal window, so a click elsewhere goes to that
        // window and rofi never sees it. Close rofi once it loses focus.
        this._focusId = global.display.connect('notify::focus-window', () => {
            if (!this._rofi)
                return;

            if (global.display.focus_window === this._rofi) {
                this._rofiHadFocus = true;
                return;
            }

            // Focus can still sit on the old window right after rofi maps.
            if (this._rofiHadFocus)
                this._rofi.delete(global.get_current_time());
        });

        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, OBJECT_PATH);
    }

    disable() {
        this._dbus.unexport();
        this._dbus = null;

        global.display.disconnect(this._createdId);
        global.display.disconnect(this._focusId);
        this._createdId = null;
        this._focusId = null;
        this._rofi = null;
    }

    _trackRofi(win) {
        this._rofi = win;
        this._rofiHadFocus = false;
        win.connect('unmanaged', () => {
            if (this._rofi === win)
                this._rofi = null;
        });
        Main.activateWindow(win);
    }

    // Most recently used first: [id, app name, icon, title, workspace (0 = all)]
    ListWindows() {
        const tracker = Shell.WindowTracker.get_default();

        return global.display.get_tab_list(Meta.TabList.NORMAL_ALL, null)
            .filter(win => !win.skip_taskbar && win.get_wm_class() !== ROFI_WM_CLASS)
            .map(win => {
                const app = tracker.get_window_app(win);
                const icon = app?.get_icon()?.to_string() ?? FALLBACK_ICON;
                const workspace = win.is_on_all_workspaces() ? 0 : win.get_workspace().index() + 1;
                return [win.get_id(), app?.get_name() ?? '', icon, win.get_title() ?? '', workspace];
            });
    }

    Activate(id) {
        const win = global.display.get_tab_list(Meta.TabList.NORMAL_ALL, null)
            .find(w => w.get_id() === id);
        if (win)
            Main.activateWindow(win);
    }
}
