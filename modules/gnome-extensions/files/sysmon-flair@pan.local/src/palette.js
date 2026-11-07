import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

// The rice's switch-theme.sh copies the active palette here ("role #hex" per
// line). Reading it at runtime means a theme switch recolours the panel live;
// colours baked into the JS would need a re-login on Wayland.
const PALETTE_PATH = GLib.build_filenamev([GLib.get_user_config_dir(), 'rice', 'palette']);

// Used when no rice palette exists: the original grey / yellow / red look.
const FALLBACK = {
    fg2: '#e6e8eb', dim: '#565b64', accent: '#e6e8eb', yellow: '#ffe14d', red: '#e06c75',
};

function hexToRgb(hex) {
    const n = parseInt(hex.slice(1), 16);
    return {r: n >> 16, g: (n >> 8) & 255, b: n & 255};
}

function read() {
    const roles = {...FALLBACK};
    try {
        const [, bytes] = GLib.file_get_contents(PALETTE_PATH);
        for (const line of new TextDecoder().decode(bytes).split('\n')) {
            const [role, hex] = line.trim().split(/\s+/);
            if (role in roles && /^#[0-9a-fA-F]{6}$/.test(hex ?? ''))
                roles[role] = hex;
        }
    } catch {
        // no rice installed: keep the fallback
    }
    return Object.fromEntries(Object.entries(roles).map(([k, v]) => [k, hexToRgb(v)]));
}

let current = read();

export function palette() {
    return current;
}

/** Re-reads the palette whenever the file changes. Returns a stop function. */
export function watchPalette(onChange) {
    const file = Gio.File.new_for_path(PALETTE_PATH);
    const monitor = file.monitor_file(Gio.FileMonitorFlags.NONE, null);
    const id = monitor.connect('changed', (_m, _f, _o, event) => {
        if (event !== Gio.FileMonitorEvent.CHANGES_DONE_HINT &&
            event !== Gio.FileMonitorEvent.CREATED)
            return;
        current = read();
        onChange?.();
    });
    return () => {
        monitor.disconnect(id);
        monitor.cancel();
    };
}

function mix(a, b, f) {
    return {
        r: Math.round(a.r + (b.r - a.r) * f),
        g: Math.round(a.g + (b.g - a.g) * f),
        b: Math.round(a.b + (b.b - a.b) * f),
    };
}

/** Linear ramp through [position, colour] stops. */
export function ramp(stops, t) {
    const x = Math.max(0, Math.min(1, t));
    for (let i = 1; i < stops.length; i++) {
        const [p1, c1] = stops[i];
        if (x <= p1) {
            const [p0, c0] = stops[i - 1];
            return mix(c0, c1, p1 > p0 ? (x - p0) / (p1 - p0) : 1);
        }
    }
    return stops[stops.length - 1][1];
}
