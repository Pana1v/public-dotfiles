// Blackhole Live: the Ember black hole over the wallpaper and behind the GDM
// login dialog. ember.png is the ray-traced frame (modules/rice/tools/
// blackhole.py base); the shader below keeps it moving: streaks orbit the
// hole, the glow wobbles and breathes, and the film grain re-rolls each frame.
// blackhole.py animate() is the same code in numpy for the lock-screen video;
// keep the two in step.
//
// Same frame as grid-live: one widget per monitor above the background actors
// (or at the bottom of the login dialog group on GDM), 24 fps, paused while a
// maximised or fullscreen window hides the desktop.
import Cogl from 'gi://Cogl';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const FPS = 24;
const LOOP = 10.0;   // seconds; every motion term below completes whole cycles

const DECLARATIONS = `
uniform float t;
uniform float seed;
uniform vec2 res;
uniform vec3 accent;
const vec2 CENTER = vec2(0.631, 0.570);
const float SHADOW_R = 0.240;
const float TAU = 6.2831853;
const float LOOP = ${LOOP.toFixed(1)};
float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
`;

const CODE = `
vec2 uv = cogl_tex_coord_in[0].xy;
float asp = res.x / res.y;
vec2 d = vec2((uv.x - CENTER.x) * asp, uv.y - CENTER.y) / SHADOW_R;
float r = max(length(d), 0.05);
float phi = atan(d.y, d.x);
float lr = log(r);
float w = TAU * t / LOOP;

// slow wobble of the whole glow around the hole
float a = 0.010 * sin(w + 3.0 * lr);
vec2 dr = vec2(cos(a) * d.x - sin(a) * d.y, sin(a) * d.x + cos(a) * d.y) * SHADOW_R;
// clamped: the wobble must not wrap the bottom edge's glow onto the top
vec3 s = texture2D(cogl_sampler0, clamp(vec2(CENTER.x + dr.x / asp, CENTER.y + dr.y), 0.5 / res, 1.0 - 0.5 / res)).rgb;

// streaks orbiting the hole, inner ones faster; none inside the shadow
float st = 0.5 * sin(3.0 * phi + 5.0 * lr + 1.3 - w)
         + 0.3 * sin(7.0 * phi + 9.0 * lr + 4.1 - 3.0 * w)
         + 0.2 * sin(13.0 * phi + 14.0 * lr + 2.2 - 7.0 * w);
float m = smoothstep(0.85, 1.25, r) * exp(-max(r - 1.0, 0.0) / 3.0);
float lum = dot(s, vec3(0.3, 0.59, 0.11));
vec3 col = s * (1.0 + 0.5 * st * m);
col += accent * 0.08 * max(st, 0.0) * m * smoothstep(0.05, 0.5, lum);
col *= 1.0 + 0.04 * sin(w);

// film grain, roughly normal (sum of three uniforms)
vec2 px = floor(uv * res);
float n = (hash(px + seed * 17.0) + hash(px * 1.7 + seed * 31.0)
         + hash(px * 2.3 + seed * 7.0) - 1.5) * 2.0;
col = col * (1.0 + 0.07 * n) + 0.004 * n;
cogl_color_out = vec4(clamp(col, 0.0, 1.0), 1.0);
`;

const EmberEffect = GObject.registerClass(
class EmberEffect extends Shell.GLSLEffect {
    vfunc_build_pipeline() {
        this.add_glsl_snippet(Cogl.SnippetHook.FRAGMENT, DECLARATIONS, CODE, true);
    }

    setup(width, height, accent) {
        this.set_uniform_float(this.get_uniform_location('res'), 2, [width, height]);
        this.set_uniform_float(this.get_uniform_location('accent'), 3, accent);
        this._t = this.get_uniform_location('t');
        this._seed = this.get_uniform_location('seed');
    }

    setTime(t, frame) {
        this.set_uniform_float(this._t, 1, [t]);
        this.set_uniform_float(this._seed, 1, [frame]);
        this.queue_repaint();
    }
});

// Accent from the rice palette as 0..1 floats.
function readAccent() {
    let accent = '#ff1f3d';
    try {
        const path = GLib.build_filenamev([GLib.get_home_dir(), '.config', 'rice', 'palette']);
        const [, bytes] = GLib.file_get_contents(path);
        for (const line of new TextDecoder().decode(bytes).split('\n')) {
            const [key, val] = line.trim().split(/\s+/);
            if (key === 'accent' && val?.startsWith('#'))
                accent = val;
        }
    } catch {
        // no palette (GDM has no home): keep the Ares accent
    }
    return [1, 3, 5].map(i => parseInt(accent.slice(i, i + 2), 16) / 255);
}

export default class BlackholeLiveExtension extends Extension {
    enable() {
        this._greeter = Main.sessionMode.isGreeter;
        this._group = this._greeter
            ? Main.screenShield._lockDialogGroup
            : Main.layoutManager._backgroundGroup;
        this._accent = readAccent();
        this._image = GLib.build_filenamev([this.path, 'ember.png']);
        this._holes = [];
        this._start = GLib.get_monotonic_time();
        this._frame = 0;

        this._build();
        this._monitorsId = Main.layoutManager.connect('monitors-changed', () => this._build());
        // A wallpaper change adds new background actors on top; stay above them.
        this._childId = this._greeter
            ? 0 : this._group.connect('child-added', () => this._raise());

        this._tickId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, Math.round(1000 / FPS), () => {
            if (!this._paused) {
                const t = ((GLib.get_monotonic_time() - this._start) / 1e6) % LOOP;
                this._frame = (this._frame + 1) % 997;
                for (const h of this._holes)
                    h.effect.setTime(t, this._frame);
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
        for (const h of this._holes)
            h.actor.destroy();
        this._holes = [];
    }

    _build() {
        this._clear();
        for (const m of Main.layoutManager.monitors) {
            // The widget paints ember.png; the effect reads it back as
            // cogl_sampler0 and moves it.
            const actor = new St.Widget({
                x: m.x, y: m.y, width: m.width, height: m.height,
                style: `background-color: black; background-image: url("file://${this._image}");` +
                    ' background-size: cover; background-position: center;',
                reactive: false,
            });
            const effect = new EmberEffect();
            actor.add_effect(effect);
            const scale = m.geometry_scale ?? 1;
            effect.setup(m.width * scale, m.height * scale, this._accent);
            this._group.add_child(actor);
            this._holes.push({actor, effect, monitor: m});
        }
        this._raise();
    }

    _raise() {
        for (const h of this._holes) {
            if (this._greeter)
                this._group.set_child_below_sibling(h.actor, null);
            else
                this._group.set_child_above_sibling(h.actor, null);
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
        return this._holes.length > 0 && this._holes.every(h => covered.has(h.monitor.index));
    }
}
