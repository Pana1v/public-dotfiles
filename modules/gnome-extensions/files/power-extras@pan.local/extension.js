// Power Extras: two small additions to Quick Settings.
//
//   - The battery pill gets a subtitle with UPower's estimate: "2h 10m left"
//     on battery, "46m to full" while charging.
//   - The power menu gets "Restart to UEFI Setup" (logind allows it for the
//     session, no root) and "Restart to Windows" (needs the helper installed
//     by modules/rice/reboot-targets.sh; hidden until it exists).
//
// Both restart items act at once, no confirmation dialog.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import UPower from 'gi://UPowerGlib';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const WINDOWS_HELPER = '/usr/local/sbin/reboot-to-windows';

function duration(seconds) {
    const total = Math.round(seconds / 60);
    const h = Math.floor(total / 60), m = total % 60;
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

function run(argv, what) {
    try {
        const proc = Gio.Subprocess.new(argv,
            Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_PIPE);
        proc.communicate_utf8_async(null, null, (p, res) => {
            const [, , stderr] = p.communicate_utf8_finish(res);
            if (!p.get_successful())
                Main.notifyError(`${what} failed`, stderr?.trim() || `exit ${p.get_exit_status()}`);
        });
    } catch (e) {
        Main.notifyError(`${what} failed`, e.message);
    }
}

export default class PowerExtras extends Extension {
    enable() {
        this._tries = 0;
        // Quick Settings builds its indicators asynchronously at startup.
        this._waitId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
            const item = Main.panel.statusArea.quickSettings?._system?._systemItem;
            if (item) {
                this._waitId = 0;
                this._setup(item);
                return GLib.SOURCE_REMOVE;
            }
            if (++this._tries > 40) {
                this._waitId = 0;
                console.warn('power-extras: Quick Settings system item not found');
                return GLib.SOURCE_REMOVE;
            }
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        if (this._waitId)
            GLib.source_remove(this._waitId);
        this._waitId = 0;
        if (this._toggle) {
            for (const [obj, id] of this._ids)
                obj.disconnect(id);
            this._toggle.subtitle = null;
        }
        this._items?.forEach(i => i.destroy());
        this._toggle = null;
        this._items = null;
        this._ids = null;
    }

    _setup(item) {
        this._ids = [];

        // ---- battery estimate ----
        this._toggle = item.powerToggle;
        const proxy = this._toggle._proxy;
        // The toggle re-syncs its title on every property change; follow it.
        this._ids.push([this._toggle, this._toggle.connect('notify::title', () => this._syncEta())]);
        if (proxy)
            this._ids.push([proxy, proxy.connect('g-properties-changed', () => this._syncEta())]);
        this._syncEta();

        // ---- power menu ----
        const menu = item.menu;
        const uefi = new PopupMenu.PopupMenuItem('Restart to UEFI Setup');
        uefi.connect('activate', () => {
            Main.panel.closeQuickSettings();
            run(['systemctl', 'reboot', '--firmware-setup'], 'Restart to UEFI Setup');
        });
        const windows = new PopupMenu.PopupMenuItem('Restart to Windows');
        windows.connect('activate', () => {
            Main.panel.closeQuickSettings();
            run(['sudo', '-n', WINDOWS_HELPER], 'Restart to Windows');
        });

        // Right after Power Off, before the Log Out group.
        const sep = menu._getMenuItems().findIndex(i => i instanceof PopupMenu.PopupSeparatorMenuItem);
        const at = sep >= 0 ? sep : undefined;
        menu.addMenuItem(uefi, at);
        menu.addMenuItem(windows, at === undefined ? undefined : at + 1);
        this._items = [uefi, windows];

        const syncWindows = () => {
            windows.visible = GLib.file_test(WINDOWS_HELPER, GLib.FileTest.IS_EXECUTABLE);
        };
        this._ids.push([menu, menu.connect('open-state-changed', (_, open) => open && syncWindows())]);
        syncWindows();
    }

    _syncEta() {
        const proxy = this._toggle?._proxy;
        if (!proxy || !proxy.IsPresent) {
            if (this._toggle)
                this._toggle.subtitle = null;
            return;
        }
        let text = null;
        switch (proxy.State) {
        case UPower.DeviceState.DISCHARGING:
            if (proxy.TimeToEmpty > 0)
                text = `${duration(proxy.TimeToEmpty)} left`;
            break;
        case UPower.DeviceState.CHARGING:
            if (proxy.TimeToFull > 0)
                text = `${duration(proxy.TimeToFull)} to full`;
            break;
        case UPower.DeviceState.FULLY_CHARGED:
            text = 'Charged';
            break;
        }
        if (this._toggle.subtitle !== text)
            this._toggle.subtitle = text;
    }
}
