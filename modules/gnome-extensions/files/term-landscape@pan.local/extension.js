// Terminal Landscape: the wallpaper's Ember black hole behind every Terminator
// window, drawn in ASCII glyphs.
//
// Terminator (VTE) can only paint a flat or translucent background, so the
// scene lives in the compositor instead: one shader widget per Terminator
// window, inserted at the bottom of the window actor's children (the same trick
// as conky-glass). The terminal paints its translucent background over it, so
// the scene shows through behind the text, and it moves and tiles with the
// window for free.
//
// The widget paints blackhole-live's ember.png (cover-fitted, like the
// wallpaper); the shader reads it back per character cell, runs the same orbit
// streaks as blackhole-live, and turns each cell's brightness into a glyph.
// Only the focused terminal animates; the others freeze on their last frame,
// dimmed.
import Cogl from 'gi://Cogl';
import GdkPixbuf from 'gi://GdkPixbuf';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const FPS = 30;
const UNFOCUSED_DIM = 0.55;
// Same as blackhole-live: hole centre and shadow radius as fractions of
// ember.png, and a loop every motion term completes whole cycles in.
const CENTER = [0.631, 0.570];
const SHADOW_R = 0.240;
const LOOP = 10.0;

const DECLARATIONS = `
uniform vec2 res;
uniform vec2 cell;
uniform vec3 hole;
uniform float t;
uniform float dim;
uniform vec3 accent;
uniform vec3 bgcol;

const float TAU = 6.2831853;
const float LOOP = ${LOOP.toFixed(1)};
const float STRENGTH = 0.85;

// 4x6 bitmaps, one hex nibble per row, top row in the high bits.
// Ramp by ink: ' ' . : - = + * o # @
float glyph(float lv) {
    if (lv < 0.5) return 0.0;
    if (lv < 1.5) return 96.0;        // 0x000060 .
    if (lv < 2.5) return 393312.0;    // 0x060060 :
    if (lv < 3.5) return 61440.0;     // 0x00F000 -
    if (lv < 4.5) return 986880.0;    // 0x0F0F00 =
    if (lv < 5.5) return 320512.0;    // 0x04E400 +
    if (lv < 6.5) return 10806432.0;  // 0xA4E4A0 *
    if (lv < 7.5) return 432480.0;    // 0x069960 o
    if (lv < 8.5) return 6250320.0;   // 0x5F5F50 #
    return 6929287.0;                 // 0x69BB87 @
}

// Bit (x, y) of a glyph without integer ops: codes stay below 2^24, so the
// float division and floor are exact.
float glyphBit(float code, vec2 g) {
    float idx = (5.0 - g.y) * 4.0 + (3.0 - g.x);
    return mod(floor(code / exp2(idx)), 2.0);
}
`;

const CODE = `
vec2 p = cogl_tex_coord_in[0].xy * res;
vec2 ci = floor(p / cell);
vec2 cc = (ci + 0.5) * cell;

// blackhole-live's motion, in units of the shadow radius (hole.z, pixels)
vec2 d = (cc - hole.xy) / hole.z;
float r = max(length(d), 0.05);
float phi = atan(d.y, d.x);
float lr = log(r);
float w = TAU * t / LOOP;
float a = 0.010 * sin(w + 3.0 * lr);
vec2 dr = vec2(cos(a) * d.x - sin(a) * d.y, sin(a) * d.x + cos(a) * d.y) * hole.z;
vec3 s = texture2D(cogl_sampler0, clamp((hole.xy + dr) / res, 0.5 / res, 1.0 - 0.5 / res)).rgb;
float st = 0.5 * sin(3.0 * phi + 5.0 * lr + 1.3 - w)
         + 0.3 * sin(7.0 * phi + 9.0 * lr + 4.1 - 3.0 * w)
         + 0.2 * sin(13.0 * phi + 14.0 * lr + 2.2 - 7.0 * w);
float m = smoothstep(0.85, 1.25, r) * exp(-max(r - 1.0, 0.0) / 3.0);
float lum = dot(s, vec3(0.3, 0.59, 0.11));
vec3 col = s * (1.0 + 0.5 * st * m);
col += accent * 0.08 * max(st, 0.0) * m * smoothstep(0.05, 0.5, lum);

// Luminance picks the glyph, the peak channel only the hue: the disk is
// saturated red, so by peak it would be a wall of @ behind the text. The 0.75
// lift keeps the photon ring visible; lower and the empty sky fills with dots.
float peak = max(col.r, max(col.g, col.b));
vec3 hue = col / max(peak, 0.001);
float I = pow(clamp(dot(col, vec3(0.3, 0.59, 0.11)), 0.0, 1.0), 0.75);
float lv = floor(I * 9.0 + 0.5);
float gp = cell.y / 8.0;
vec2 g = floor((p - ci * cell) / gp) - vec2(1.0, 1.0);
float lit = 0.0;
if (g.x >= 0.0 && g.x <= 3.0 && g.y >= 0.0 && g.y <= 5.0)
    lit = glyphBit(glyph(lv), g);

vec3 outc = bgcol + hue * (lit * I * STRENGTH + I * 0.05);
outc = mix(bgcol, outc, dim);
cogl_color_out = vec4(min(outc, vec3(1.0)), 1.0);
`;

const EmberAsciiEffect = GObject.registerClass(
class EmberAsciiEffect extends Shell.GLSLEffect {
    vfunc_build_pipeline() {
        this.add_glsl_snippet(Cogl.SnippetHook.FRAGMENT, DECLARATIONS, CODE, true);
    }

    setup(colours) {
        this._loc = {};
        for (const name of ['res', 'cell', 'hole', 't', 'dim'])
            this._loc[name] = this.get_uniform_location(name);
        for (const name of ['accent', 'bgcol'])
            this.set_uniform_float(this.get_uniform_location(name), 3, colours[name]);
        this.setDim(1.0);
    }

    setSize(res, cell, hole) {
        this.set_uniform_float(this._loc.res, 2, res);
        this.set_uniform_float(this._loc.cell, 2, cell);
        this.set_uniform_float(this._loc.hole, 3, hole);
        this.queue_repaint();
    }

    setDim(v) {
        this.set_uniform_float(this._loc.dim, 1, [v]);
        this.queue_repaint();
    }

    setTime(t) {
        this.set_uniform_float(this._loc.t, 1, [t]);
        this.queue_repaint();
    }
});

// Rice palette roles as 0..1 floats.
function readPalette() {
    const hex = {accent: '#ff1f3d', bg: '#0a0506'};
    try {
        const path = GLib.build_filenamev([GLib.get_home_dir(), '.config', 'rice', 'palette']);
        const [, bytes] = GLib.file_get_contents(path);
        for (const line of new TextDecoder().decode(bytes).split('\n')) {
            const [key, val] = line.trim().split(/\s+/);
            if (key in hex && val?.startsWith('#'))
                hex[key] = val;
        }
    } catch {
        // no palette yet: keep the Ares defaults
    }
    const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
    return {accent: rgb(hex.accent), bgcol: rgb(hex.bg)};
}

function isTerminator(metaWindow) {
    const id = `${metaWindow.get_wm_class() ?? ''} ${metaWindow.get_gtk_application_id?.() ?? ''}`;
    return /terminator/i.test(id);
}

export default class TermLandscapeExtension extends Extension {
    enable() {
        this._colours = readPalette();
        // One image for wallpaper and terminals: the gnome-extensions module
        // installs blackhole-live next to this extension.
        this._image = GLib.build_filenamev([GLib.path_get_dirname(this.path), 'blackhole-live@pan.local', 'ember.png']);
        const [, iw, ih] = GdkPixbuf.Pixbuf.get_file_info(this._image);
        this._imageSize = [iw || 1920, ih || 1200];
        this._tracked = new Map();
        this._start = GLib.get_monotonic_time();

        this._createdId = global.display.connect('window-created', (_, mw) => {
            // The actor and app id are not ready until the next idle.
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                this._consider(mw);
                return GLib.SOURCE_REMOVE;
            });
        });
        this._focusId = global.display.connect('notify::focus-window', () => this._applyFocus());
        for (const actor of global.get_window_actors())
            this._consider(actor.meta_window);

        this._tickId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, Math.round(1000 / FPS), () => {
            this._tick();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        GLib.source_remove(this._tickId);
        global.display.disconnect(this._createdId);
        global.display.disconnect(this._focusId);
        for (const mw of [...this._tracked.keys()])
            this._untrack(mw);
        this._tracked = null;
    }

    _consider(mw) {
        if (!this._tracked || !mw || this._tracked.has(mw))
            return;
        // Wayland clients may set their app id after the first idle: retry once shown.
        if (!mw.get_wm_class() && !mw._termLandscapeRetry) {
            mw._termLandscapeRetry = mw.connect('shown', () => {
                mw.disconnect(mw._termLandscapeRetry);
                this._consider(mw);
            });
            return;
        }
        if (!isTerminator(mw))
            return;
        const actor = mw.get_compositor_private();
        if (!actor)
            return;

        // The effect reads the painted image back as cogl_sampler0.
        const layer = new St.Widget({
            reactive: false,
            style: `background-color: black; background-image: url("file://${this._image}");` +
                ' background-size: cover; background-position: center;',
        });
        const effect = new EmberAsciiEffect();
        layer.add_effect(effect);
        effect.setup(this._colours);
        actor.insert_child_below(layer, null);

        const entry = {layer, effect, ids: []};
        this._tracked.set(mw, entry);
        // The layer dies with the window actor, often before 'unmanaged'.
        layer.connect('destroy', () => {
            entry.layer = null;
        });
        entry.ids.push(mw.connect('size-changed', () => this._layout(mw, entry)));
        entry.ids.push(mw.connect('unmanaged', () => this._untrack(mw)));
        this._layout(mw, entry);
        this._applyFocus();
    }

    // Cover the frame (not the shadow margin of the buffer), in physical pixels.
    _layout(mw, entry) {
        if (!entry.layer)
            return;
        const buf = mw.get_buffer_rect();
        const frame = mw.get_frame_rect();
        entry.layer.set_position(frame.x - buf.x, frame.y - buf.y);
        entry.layer.set_size(frame.width, frame.height);
        const scale = global.display.get_monitor_scale(mw.get_monitor()) || 1;
        const gp = Math.max(1, Math.round(2 * scale));
        // Where the cover-fitted image puts the hole in this window.
        const [W, H] = [frame.width * scale, frame.height * scale];
        const [iw, ih] = this._imageSize;
        const k = Math.max(W / iw, H / ih);
        const hole = [W / 2 + (CENTER[0] - 0.5) * iw * k, H / 2 + (CENTER[1] - 0.5) * ih * k, SHADOW_R * ih * k];
        entry.effect.setSize([W, H], [6 * gp, 8 * gp], hole);
    }

    _applyFocus() {
        const focused = global.display.focus_window;
        for (const [mw, entry] of this._tracked) {
            if (entry.layer)
                entry.effect.setDim(mw === focused ? 1.0 : UNFOCUSED_DIM);
        }
    }

    _tick() {
        const mw = global.display.focus_window;
        const entry = mw && this._tracked.get(mw);
        if (!entry?.layer || mw.minimized)
            return;
        entry.effect.setTime(((GLib.get_monotonic_time() - this._start) / 1e6) % LOOP);
    }

    _untrack(mw) {
        const entry = this._tracked?.get(mw);
        if (!entry)
            return;
        for (const id of entry.ids)
            mw.disconnect(id);
        entry.layer?.destroy();
        this._tracked.delete(mw);
    }
}
