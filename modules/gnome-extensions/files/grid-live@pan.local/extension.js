// Grid Live: the wallpaper's Tron grid, drawn by a fragment shader and sliding
// toward the viewer. Same horizon and perspective as modules/rice/tools/grid.py,
// so it lines up with the static wallpaper it covers.
//
// One plain widget per monitor sits on top of the background actors (or, on the
// GDM login screen, at the bottom of the login dialog group); the shader
// replaces its pixels. It ticks at 30 fps and stops while a maximised or
// fullscreen window hides the desktop, so it costs nothing under normal work.
import Cogl from 'gi://Cogl';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const FPS = 30;
const CELLS_PER_SECOND = 0.5;

const DECLARATIONS = `
uniform float phase;
uniform vec2 res;
uniform vec3 accent;
uniform vec3 bgcol;
uniform vec3 fgcol;
const float HZ = 0.55;
const float CELL = 0.42;
`;

// Ground plane: camera one unit up, focal length = pixels below the horizon,
// so depth 1 lands on the bottom edge (grid.py uses the same numbers).
const CODE = `
vec2 p = cogl_tex_coord_in[0].xy * res;
float s = res.x / 1920.0;
float hz = HZ * res.y;
float F = res.y - hz;
float dy = p.y - hz;
vec3 col = bgcol;

float dist = abs(dy) / res.y;
col += accent * (dy < 0.0
    ? 0.27 * pow(max(0.0, 1.0 - dist * 6.0), 2.0)
    : 0.16 * pow(max(0.0, 1.0 - dist * 14.0), 2.0));

if (dy > 0.5) {
    float z = F / dy;
    float X = (p.x - 0.5 * res.x) * z / F;
    float pxX = abs(fract(X / CELL + 0.5) - 0.5) * CELL * F / z;
    float pxZ = abs(fract((z - 1.0) / CELL + phase + 0.5) - 0.5) * CELL * F / (z * z);
    float w2 = 0.9 * s * s;
    float t = dy / F;
    float depth = clamp(0.05 + 1.1 * pow(t, 0.7), 0.0, 1.0);
    // lines closer than a few pixels apart become a flat glow (no moire)
    float fx = smoothstep(2.0, 10.0, CELL * F / z);
    float fz = smoothstep(2.0, 10.0, CELL * F / (z * z));
    float lx = (exp(-pxX * pxX / w2) + 0.45 * exp(-pxX / (4.0 * s))) * fx;
    float lz = (exp(-pxZ * pxZ / w2) + 0.45 * exp(-pxZ / (4.0 * s))) * fz;
    col += accent * depth * max(lx, lz);
    col += accent * depth * 0.10 * (1.0 - fz);
}

float hd = abs(dy);
col += accent * (exp(-hd * hd / 2.0) + 0.35 * exp(-hd / (10.0 * s)));
col += fgcol * 0.5 * exp(-hd * hd / 0.8);
cogl_color_out = vec4(min(col, vec3(1.0)), 1.0);
`;

const GridEffect = GObject.registerClass(
class GridEffect extends Shell.GLSLEffect {
    vfunc_build_pipeline() {
        this.add_glsl_snippet(Cogl.SnippetHook.FRAGMENT, DECLARATIONS, CODE, true);
    }

    setup(width, height, colours) {
        this.set_uniform_float(this.get_uniform_location('res'), 2, [width, height]);
        this.set_uniform_float(this.get_uniform_location('accent'), 3, colours.accent);
        this.set_uniform_float(this.get_uniform_location('bgcol'), 3, colours.bg);
        this.set_uniform_float(this.get_uniform_location('fgcol'), 3, colours.fg);
        this._phase = this.get_uniform_location('phase');
    }

    setPhase(v) {
        this.set_uniform_float(this._phase, 1, [v]);
        this.queue_repaint();
    }
});

// accent/bg/fg from the rice palette, as 0..1 floats.
function readPalette() {
    const cols = {accent: '#ff1f3d', bg: '#0a0506', fg: '#ffe9eb'};
    try {
        const path = GLib.build_filenamev([GLib.get_home_dir(), '.config', 'rice', 'palette']);
        const [, bytes] = GLib.file_get_contents(path);
        for (const line of new TextDecoder().decode(bytes).split('\n')) {
            const [key, val] = line.trim().split(/\s+/);
            if (key in cols && val?.startsWith('#'))
                cols[key] = val;
        }
    } catch {
        // no palette yet: keep the Ares defaults
    }
    const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
    return {accent: rgb(cols.accent), bg: rgb(cols.bg), fg: rgb(cols.fg)};
}

export default class GridLiveExtension extends Extension {
    enable() {
        // Greeter: behind the login dialog. Desktop: above the wallpaper actors.
        this._greeter = Main.sessionMode.isGreeter;
        this._group = this._greeter
            ? Main.screenShield._lockDialogGroup
            : Main.layoutManager._backgroundGroup;
        this._colours = readPalette();
        this._grids = [];
        this._start = GLib.get_monotonic_time();

        this._build();
        this._monitorsId = Main.layoutManager.connect('monitors-changed', () => this._build());
        // A wallpaper change adds new background actors on top; stay above them.
        this._childId = this._greeter
            ? 0 : this._group.connect('child-added', () => this._raise());

        this._tickId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, Math.round(1000 / FPS), () => {
            if (!this._paused) {
                const secs = (GLib.get_monotonic_time() - this._start) / 1e6;
                const phase = (secs * CELLS_PER_SECOND) % 1;
                for (const g of this._grids)
                    g.effect.setPhase(phase);
            }
            return GLib.SOURCE_CONTINUE;
        });
        this._checkId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
            this._paused = !this._greeter && this._desktopHidden();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        for (const id of [this._tickId, this._checkId])
            if (id)
                GLib.source_remove(id);
        this._tickId = this._checkId = 0;
        Main.layoutManager.disconnect(this._monitorsId);
        if (this._childId)
            this._group.disconnect(this._childId);
        this._clear();
        this._group = null;
    }

    _clear() {
        for (const g of this._grids)
            g.actor.destroy();
        this._grids = [];
    }

    _build() {
        this._clear();
        for (const m of Main.layoutManager.monitors) {
            const actor = new St.Widget({
                x: m.x, y: m.y, width: m.width, height: m.height,
                style: 'background-color: black;',
                reactive: false,
            });
            const effect = new GridEffect();
            actor.add_effect(effect);
            // the shader works in physical pixels so lines stay 1px sharp
            const scale = m.geometry_scale ?? 1;
            effect.setup(m.width * scale, m.height * scale, this._colours);
            this._group.add_child(actor);
            this._grids.push({actor, effect, monitor: m});
        }
        this._raise();
    }

    _raise() {
        for (const g of this._grids) {
            if (this._greeter)
                this._group.set_child_below_sibling(g.actor, null);
            else
                this._group.set_child_above_sibling(g.actor, null);
        }
    }

    // True when every monitor is covered by a maximised or fullscreen window.
    _desktopHidden() {
        const ws = global.workspace_manager.get_active_workspace();
        const covered = new Set();
        for (const wa of global.get_window_actors()) {
            const w = wa.meta_window;
            if (!w || w.minimized || !w.located_on_workspace(ws))
                continue;
            const max = typeof w.is_maximized === 'function'
                ? w.is_maximized() : w.get_maximized?.() === 3;
            if (max || w.is_fullscreen())
                covered.add(w.get_monitor());
        }
        return this._grids.length > 0 && this._grids.every(g => covered.has(g.monitor.index));
    }
}
