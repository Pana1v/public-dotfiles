// Terminal Landscape: an animated loss landscape behind every Terminator window.
//
// Terminator (VTE) can only paint a flat or translucent background, so the
// animation lives in the compositor instead: one shader widget per Terminator
// window, inserted at the bottom of the window actor's children (the same trick
// as conky-glass). The terminal paints its 50% translucent background over it,
// so the scene shows through behind the text, and it moves and tiles with the
// window for free.
//
// The scene is a Tron wireframe of a loss surface whose minima drift, as if the
// model were retraining, drawn as ASCII glyphs. A genetic-algorithm population
// hunts the minima: each generation keeps its fittest agent (elitism), spawns
// mutated children around it, and sends two random explorers out for diversity.
//
// Cost: the GA and the well positions run here on the CPU (a few dozen numbers
// per frame) and reach the shader as uniforms. The shader draws ridgelines
// front to back and stops at the first hit, so no ray marching. Only the
// focused terminal animates; the others freeze on their last frame, dimmed.
import Cogl from 'gi://Cogl';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const FPS = 30;
const GEN_SECONDS = 7;
const N_AGENTS = 12;      // must match agents[] in the shader
const N_WELLS = 3;        // must match wells[] in the shader
const UNFOCUSED_DIM = 0.55;
// Ripple terms use 0.4t and 0.3t: both repeat every 20*pi s, so wrapping the
// shader clock there is seamless and keeps float32 precise forever.
const SHADER_PERIOD = 20 * Math.PI;

// Camera and surface, shared by the shader and the CPU projection below.
const HZ = 0.28;          // horizon, as a fraction of height from the top
const CAM_H = 1.3;        // camera height above the zero-loss plane
const EXAG = 1.6;         // vertical exaggeration, so valleys read as 3D
const F = 1.0 - HZ;       // focal length in screen fractions
const Z0 = 0.8;           // nearest ridge depth
const ZR = 1.15;          // each ridge 15% farther: even spacing on screen
const N_RIDGES = 16;
const LOSS_BASE = 0.35;
const RIPPLE = 0.06;

// Per well: [cx, cz, depth, width, wx, wz, phase x, phase z].
const WELLS = [
    [-1.1, 2.2, 0.55, 0.5, 0.23, 0.17, 0.0, 1.3],
    [1.0, 3.3, 0.42, 0.8, 0.19, 0.13, 2.1, 0.4],
    [0.0, 4.8, 0.65, 1.2, 0.11, 0.21, 4.2, 2.8],
];

const DECLARATIONS = `
uniform vec2 res;
uniform vec2 cell;
uniform float time;
uniform float dim;
uniform vec3 accent;
uniform vec3 bgcol;
uniform vec3 fgcol;
uniform vec3 good;
uniform vec4 wells[${N_WELLS}];
uniform vec3 agents[${N_AGENTS}];

const float HZ = ${HZ.toFixed(4)};
const float CAM_H = ${CAM_H.toFixed(4)};
const float F = ${F.toFixed(4)};
const float EXAG = ${EXAG.toFixed(4)};
const float Z0 = ${Z0.toFixed(4)};
const float ZR = ${ZR.toFixed(4)};
const float STRENGTH = 0.85;

float loss(vec2 P) {
    float h = ${LOSS_BASE.toFixed(4)};
    for (int i = 0; i < ${N_WELLS}; i++) {
        vec2 d = P - wells[i].xy;
        h -= wells[i].z * exp(-dot(d, d) / wells[i].w);
    }
    return h + ${RIPPLE.toFixed(4)} * sin(2.1 * P.x + 0.4 * time) * cos(1.7 * P.y - 0.3 * time);
}

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
vec2 uv = cc / res;
float asp = res.x / res.y;

vec3 col = accent;
float I = 0.0;
bool hit = false;
float halfLine = 0.5 * cell.y / res.y;

// Ridgelines from near to far. A cell under ridge k's curve belongs to the
// surface patch just behind ridge k-1, which hides everything farther back.
for (int k = 0; k < ${N_RIDGES}; k++) {
    float z = Z0 * pow(ZR, float(k));
    float X = (uv.x - 0.5) * asp * z;
    float h = loss(vec2(X, z));
    float yk = HZ + (CAM_H - EXAG * h) * F / z;
    if (uv.y >= yk - halfLine) {
        float d = (uv.y - yk) * res.y / cell.y;
        float ridge = 0.8 * (1.0 - smoothstep(0.2, 0.9, abs(d)));
        float perCell = asp * z * cell.x / res.x;
        float xd = abs(fract(X * 1.2 + 0.5) - 0.5) / 1.2;
        float rail = 1.0 - smoothstep(0.5 * perCell, 1.3 * perCell, xd);
        float fade = 1.0 - 0.75 * float(k) / ${N_RIDGES}.0;
        I = (max(ridge, 0.45 * rail) + 0.05) * fade;
        col = mix(good, accent, smoothstep(-0.15, 0.35, h));
        hit = true;
        break;
    }
}

if (!hit) {
    float horizon = HZ + (CAM_H - EXAG * ${LOSS_BASE.toFixed(4)}) * F / (Z0 * pow(ZR, ${N_RIDGES}.0));
    I = 0.3 * exp(-abs(uv.y - horizon) * res.y / (cell.y * 3.0));
    float r = fract(sin(dot(ci, vec2(12.9898, 78.233))) * 43758.5453);
    if (r > 0.993) {
        I = max(I, 0.14 + 0.08 * sin(time * 2.0 + r * 60.0));
        col = fgcol;
    }
}

// GA agents, always on top. agents[i] = (u, v, fitness); fitness + 2 marks the elite.
for (int i = 0; i < ${N_AGENTS}; i++) {
    vec3 a = agents[i];
    float elite = step(1.5, a.z);
    float fit = a.z - 2.0 * elite;
    vec2 dc = (cc - a.xy * res) / cell;
    if (abs(dc.x) < 0.5 && abs(dc.y) < 0.5) {
        I = 1.0;
        col = mix(good, fgcol, elite);
    } else {
        float r = length(dc * vec2(1.0, 1.35));
        float halo = (1.0 - smoothstep(0.6, 2.6, r)) * 0.75 * (0.4 + 0.6 * fit);
        if (halo > I) {
            I = halo;
            col = good;
        }
    }
}

float lv = floor(clamp(I, 0.0, 1.0) * 9.0 + 0.5);
float gp = cell.y / 8.0;
vec2 g = floor((p - ci * cell) / gp) - vec2(1.0, 1.0);
float lit = 0.0;
if (g.x >= 0.0 && g.x <= 3.0 && g.y >= 0.0 && g.y <= 5.0)
    lit = glyphBit(glyph(lv), g);

vec3 outc = bgcol + col * (lit * I * STRENGTH + I * 0.05);
outc = mix(bgcol, outc, dim);
cogl_color_out = vec4(min(outc, vec3(1.0)), 1.0);
`;

const LandscapeEffect = GObject.registerClass(
class LandscapeEffect extends Shell.GLSLEffect {
    vfunc_build_pipeline() {
        this.add_glsl_snippet(Cogl.SnippetHook.FRAGMENT, DECLARATIONS, CODE, true);
    }

    setup(colours) {
        this._loc = {};
        for (const name of ['res', 'cell', 'time', 'dim', 'wells', 'agents'])
            this._loc[name] = this.get_uniform_location(name);
        for (const name of ['accent', 'bgcol', 'fgcol', 'good'])
            this.set_uniform_float(this.get_uniform_location(name), 3, colours[name]);
        this.setDim(1.0);
    }

    setSize(res, cell) {
        this.set_uniform_float(this._loc.res, 2, res);
        this.set_uniform_float(this._loc.cell, 2, cell);
        this.queue_repaint();
    }

    setDim(v) {
        this.set_uniform_float(this._loc.dim, 1, [v]);
        this.queue_repaint();
    }

    setFrame(time, wells, agents) {
        this.set_uniform_float(this._loc.time, 1, [time]);
        this.set_uniform_float(this._loc.wells, 4, wells);
        this.set_uniform_float(this._loc.agents, 3, agents);
        this.queue_repaint();
    }
});

// Rice palette roles as 0..1 floats. "green" is the palette's good-state colour.
function readPalette() {
    const hex = {accent: '#ff1f3d', bg: '#0a0506', fg: '#ffe9eb', green: '#52e5ff'};
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
    return {accent: rgb(hex.accent), bgcol: rgb(hex.bg), fgcol: rgb(hex.fg), good: rgb(hex.green)};
}

// --- The model, mirrored from the shader so agents sit on the surface. ---

function wellsAt(t) {
    return WELLS.map(([cx, cz, a, s, wx, wz, px, pz], i) => ({
        x: cx + 0.9 * Math.sin(t * wx + px),
        z: cz + 0.8 * Math.cos(t * wz + pz),
        a: a * (0.85 + 0.15 * Math.sin(t * 0.37 + i)),
        s,
    }));
}

function lossAt(X, Z, t, wells) {
    let h = LOSS_BASE;
    for (const w of wells)
        h -= w.a * Math.exp(-((X - w.x) ** 2 + (Z - w.z) ** 2) / w.s);
    return h + RIPPLE * Math.sin(2.1 * X + 0.4 * t) * Math.cos(1.7 * Z - 0.3 * t);
}

function gauss() {
    const u = 1 - Math.random();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * Math.random());
}

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

class Population {
    constructor() {
        this._gen = -1;
        this._elite = [0, 3.5];
        this._spawned = [];
        this.agents = [];   // [{X, Z, h, fit}] from the latest update
    }

    update(t, wells) {
        const gen = Math.floor(t / GEN_SECONDS);
        if (gen !== this._gen) {
            if (this.agents.length) {
                const best = this.agents.reduce((b, a) => (a.fit > b.fit ? a : b));
                this._elite = [best.X, best.Z];
            }
            this._spawn(wells);
            this._gen = gen;
        }
        // Descend for most of the generation, then settle so selection reads clearly.
        const tau = t / GEN_SECONDS - gen;
        const e = 1 - (1 - Math.min(1, tau / 0.8)) ** 3;
        this.agents = this._spawned.map(s => {
            const w = wells[s.basin];
            const X = s.X + (w.x + s.mx * (1 - 0.6 * e) - s.X) * e;
            const Z = s.Z + (w.z + s.mz * (1 - 0.6 * e) - s.Z) * e;
            const h = lossAt(X, Z, t, wells);
            return {X, Z, h, fit: clamp((0.42 - h) / 0.75, 0, 1)};
        });
    }

    _spawn(wells) {
        this._spawned = [];
        for (let i = 0; i < N_AGENTS; i++) {
            let X, Z;
            if (i === 0) {
                [X, Z] = this._elite;                       // elitism
            } else if (i < N_AGENTS - 2) {
                X = this._elite[0] + 0.9 * gauss();         // mutated children
                Z = this._elite[1] + 0.9 * gauss();
            } else {
                X = -2.4 + 4.8 * Math.random();             // explorers
                Z = 1.2 + 4.6 * Math.random();
            }
            X = clamp(X, -3, 3);
            Z = clamp(Z, 1.0, 6.0);
            // Each agent falls into the basin pulling hardest at its spawn point.
            let basin = 0, pull = -1;
            wells.forEach((w, j) => {
                const p = w.a * Math.exp(-((X - w.x) ** 2 + (Z - w.z) ** 2) / w.s);
                if (p > pull) {
                    pull = p;
                    basin = j;
                }
            });
            this._spawned.push({X, Z, basin, mx: 0.25 * gauss(), mz: 0.25 * gauss()});
        }
    }
}

function isTerminator(metaWindow) {
    const id = `${metaWindow.get_wm_class() ?? ''} ${metaWindow.get_gtk_application_id?.() ?? ''}`;
    return /terminator/i.test(id);
}

export default class TermLandscapeExtension extends Extension {
    enable() {
        this._colours = readPalette();
        this._tracked = new Map();
        this._population = new Population();
        this._flatAgents = new Array(3 * N_AGENTS).fill(0);
        this._flatWells = new Array(4 * N_WELLS).fill(0);
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
        this._population = null;
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

        const layer = new St.Widget({reactive: false});
        const effect = new LandscapeEffect();
        layer.add_effect(effect);
        effect.setup(this._colours);
        actor.insert_child_below(layer, null);

        const entry = {layer, effect, asp: 1, ids: []};
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
        entry.asp = frame.width / Math.max(1, frame.height);
        entry.effect.setSize([frame.width * scale, frame.height * scale], [6 * gp, 8 * gp]);
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

        const t = (GLib.get_monotonic_time() - this._start) / 1e6;
        const wells = wellsAt(t);
        this._population.update(t, wells);

        // Filled in place every frame: no per-frame garbage for the shell's GC.
        const agents = this._population.agents;
        let eliteFit = 0;
        for (const a of agents)
            eliteFit = Math.max(eliteFit, a.fit);
        const flatAgents = this._flatAgents;
        agents.forEach((a, i) => {
            flatAgents[3 * i] = a.X / (entry.asp * a.Z) + 0.5;
            flatAgents[3 * i + 1] = HZ + (CAM_H - EXAG * a.h) * F / a.Z;
            flatAgents[3 * i + 2] = a.fit === eliteFit ? a.fit + 2 : a.fit;
        });
        const flatWells = this._flatWells;
        wells.forEach((w, i) => {
            flatWells[4 * i] = w.x;
            flatWells[4 * i + 1] = w.z;
            flatWells[4 * i + 2] = w.a;
            flatWells[4 * i + 3] = w.s;
        });
        entry.effect.setFrame(t % SHADER_PERIOD, flatWells, flatAgents);
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
