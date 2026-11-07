// Conky Glass: blur the desktop behind each conky widget so its translucent
// fill reads as frosted glass.
//
// Blur my Shell only blurs normal and dialog windows, and conky runs as a
// desktop-type window, so it never gets blurred there. This puts blur strips
// inside each conky window actor (bottom of its children, like Blur my Shell
// does), so they move and stack with the window for free.
//
// A blur actor can only be a rectangle, so the wings' slanted inner corners
// are approximated with a few steps. Each step stays inside the outline, so
// no blur shows outside the glass; the leftover slivers are a few pixels wide.
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const RADIUS = 30;
// The clock has no glass panel, only rings, so it stays sharp.
const SKIP = new Set(['ConkyClock']);

// Matches modules/conky/files/conky/Common/wing.lua: MARGIN and SLANT.
const WING_MARGIN = 16;
const WING_SLANT = 60;
const WING_STEPS = 3;

// [x, y, width, height] rectangles covering the glass, in window coordinates.
function wingRects(side, w, h) {
    const m = WING_MARGIN, s = WING_SLANT, step = s / WING_STEPS;
    const ww = w - 2 * m;
    const rects = [[m, m + s, ww, h - 2 * m - 2 * s]];
    for (let k = 0; k < WING_STEPS; k++) {
        // Width at the narrow end of the step keeps the strip inside the slant.
        const width = ww - s + k * step;
        rects.push([m, m + k * step, width, step]);
        rects.push([m, h - m - (k + 1) * step, width, step]);
    }
    if (side === 'right')
        return rects.map(([x, y, rw, rh]) => [w - x - rw, y, rw, rh]);
    return rects;
}

function glassRects(wmClass, w, h) {
    if (wmClass === 'ConkyWingL')
        return wingRects('left', w, h);
    if (wmClass === 'ConkyWingR')
        return wingRects('right', w, h);
    // Single-card widgets (flat.lua card) fill the whole window.
    return [[0, 0, w, h]];
}

function blurEffect() {
    const effect = new Shell.BlurEffect({mode: Shell.BlurMode.BACKGROUND, brightness: 1.0});
    // GNOME 46 renamed sigma to radius.
    if ('radius' in effect)
        effect.radius = RADIUS;
    else
        effect.sigma = RADIUS / 2;
    return effect;
}

export default class ConkyGlass extends Extension {
    enable() {
        this._tracked = new Map();
        this._idle = 0;
        this._createdId = global.display.connect('window-created', (_, metaWindow) => {
            // The window actor and X11 class are not ready until the next idle.
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                this._track(metaWindow);
                return GLib.SOURCE_REMOVE;
            });
        });
        for (const actor of global.get_window_actors())
            this._track(actor.meta_window);
    }

    disable() {
        global.display.disconnect(this._createdId);
        for (const metaWindow of [...this._tracked.keys()])
            this._untrack(metaWindow);
        this._tracked = null;
    }

    _track(metaWindow) {
        if (!this._tracked || this._tracked.has(metaWindow))
            return;
        const wmClass = metaWindow.get_wm_class() ?? '';
        if (!wmClass.startsWith('Conky') || SKIP.has(wmClass))
            return;
        const actor = metaWindow.get_compositor_private();
        if (!actor)
            return;

        const holder = new St.Widget({reactive: false});
        actor.insert_child_below(holder, null);
        const entry = {wmClass, actor, holder, size: '', ids: []};
        this._tracked.set(metaWindow, entry);

        // The holder is a child of the window actor, so mutter destroys it with
        // the actor, often before 'unmanaged' fires. Drop the reference then so
        // _untrack never touches a disposed widget.
        holder.connect('destroy', () => {
            entry.holder = null;
        });

        entry.ids.push([metaWindow, metaWindow.connect('size-changed', () => this._shape(entry, metaWindow))]);
        entry.ids.push([metaWindow, metaWindow.connect('unmanaged', () => this._untrack(metaWindow))]);
        this._shape(entry, metaWindow);
    }

    _shape(entry, metaWindow) {
        const rect = metaWindow.get_buffer_rect();
        const key = `${rect.width}x${rect.height}`;
        if (key === entry.size || !entry.holder)
            return;
        entry.size = key;
        entry.holder.destroy_all_children();
        for (const [x, y, width, height] of glassRects(entry.wmClass, rect.width, rect.height)) {
            if (width <= 0 || height <= 0)
                continue;
            const strip = new St.Widget({x, y, width, height, reactive: false});
            strip.add_effect(blurEffect());
            entry.holder.add_child(strip);
        }
    }

    _untrack(metaWindow) {
        const entry = this._tracked?.get(metaWindow);
        if (!entry)
            return;
        for (const [obj, id] of entry.ids)
            obj.disconnect(id);
        entry.holder?.destroy();
        this._tracked.delete(metaWindow);
    }
}
