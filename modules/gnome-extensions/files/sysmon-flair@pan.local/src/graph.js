import Cairo from 'cairo';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {palette, ramp} from './palette.js';

const RGB_MAX = 255;


/**
 * Load colour, cool to hot, from the rice palette.
 *
 * The stock extension flips a single class at 80%, so a machine at 79% and one
 * at 20% look identical. A continuous ramp makes the panel readable at a glance
 * without having to parse the number. Text stays its normal colour while idle,
 * warms to the accent, then yellow at 80% and red when pinned.
 */
export function loadColor(t) {
    const p = palette();
    return ramp([[0, p.fg2], [0.3, p.fg2], [0.6, p.accent], [0.8, p.yellow], [1, p.red]], t);
}

/** Same ramp for glowing edges: starts at the dim role so idle stays quiet. */
export function edgeColor(t) {
    const p = palette();
    return ramp([[0, p.dim], [0.55, p.accent], [0.8, p.yellow], [1, p.red]], t);
}

export function cssColor({r, g, b}, alpha = 1) {
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/** Maps a temperature in Celsius onto the same ramp. */
export function tempFraction(celsius) {
    const COOL = 40;
    const HOT = 92;
    return (celsius - COOL) / (HOT - COOL);
}

/**
 * Fixed-capacity history buffer drawn as a filled area chart.
 *
 * Holding the samples in a ring buffer means a constant memory footprint no
 * matter how long the session runs, and no per-tick array shifting.
 */
export const Sparkline = GObject.registerClass(
class Sparkline extends St.DrawingArea {
    constructor({capacity, width, styleClass, colorFn}) {
        super({
            style_class: styleClass,
            width,
            y_expand: true,
        });

        this._capacity = capacity;
        this._values = new Float64Array(capacity);
        this._head = 0;
        this._filled = 0;
        this._colorFn = colorFn ?? loadColor;

        this.connect('repaint', () => this._draw());
    }

    push(value) {
        this._values[this._head] = Math.max(0, Math.min(1, value));
        this._head = (this._head + 1) % this._capacity;
        this._filled = Math.min(this._filled + 1, this._capacity);

        if (this.mapped)
            this.queue_repaint();
    }

    get latest() {
        const index = (this._head - 1 + this._capacity) % this._capacity;
        return this._filled === 0 ? 0 : this._values[index];
    }

    /** Oldest to newest, so the chart reads left to right like time. */
    _ordered() {
        const out = new Array(this._filled);
        const start = (this._head - this._filled + this._capacity) % this._capacity;

        for (let i = 0; i < this._filled; i++)
            out[i] = this._values[(start + i) % this._capacity];

        return out;
    }

    /**
     * Dot-matrix history, like the conky bars: one column of dots per time
     * step, lit from the bottom up to the load, unlit dots dim. The newest
     * column sits at the right edge and is drawn a touch brighter.
     */
    _draw() {
        const cr = this.get_context();
        const [width, height] = this.get_surface_size();
        const values = this._ordered();

        const PITCH = 4;
        const R = 1.1;
        const cols = Math.max(1, Math.floor(width / PITCH));
        const rows = Math.max(1, Math.floor(height / PITCH));
        const x0 = width - cols * PITCH + PITCH / 2;
        const y0 = height - (height - rows * PITCH) / 2 - PITCH / 2;

        // Resample the newest samples onto the columns, right-aligned.
        const sample = c => {
            const back = cols - 1 - c;
            const span = this._capacity / cols;
            const i = values.length - 1 - Math.floor(back * span);
            return i >= 0 ? values[i] : null;
        };

        const {r, g, b} = this._colorFn(this.latest);
        const unlit = palette().select ?? {r: 74, g: 22, b: 27};
        const dot = (c, row) => {
            cr.newSubPath();
            cr.arc(x0 + c * PITCH, y0 - row * PITCH, R, 0, 2 * Math.PI);
        };

        cr.setSourceRGBA(unlit.r / RGB_MAX, unlit.g / RGB_MAX, unlit.b / RGB_MAX, 0.55);
        const lit = [];
        for (let c = 0; c < cols; c++) {
            const v = sample(c);
            const n = v === null ? 0 : Math.max(v > 0.01 ? 1 : 0, Math.round(v * rows));
            lit.push(n);
            for (let row = n; row < rows; row++)
                dot(c, row);
        }
        cr.fill();

        cr.setSourceRGBA(r / RGB_MAX, g / RGB_MAX, b / RGB_MAX, 0.75);
        for (let c = 0; c < cols - 1; c++) {
            for (let row = 0; row < lit[c]; row++)
                dot(c, row);
        }
        cr.fill();

        cr.setSourceRGBA(r / RGB_MAX, g / RGB_MAX, b / RGB_MAX, 1);
        for (let row = 0; row < lit[cols - 1]; row++)
            dot(cols - 1, row);
        cr.fill();

        cr.$dispose();
    }
});

/** Horizontal bar used for per-core load in the detail menu. */
export const LoadBar = GObject.registerClass(
class LoadBar extends St.DrawingArea {
    constructor({height = 6} = {}) {
        super({
            style_class: 'sysmon-loadbar',
            height,
            x_expand: true,
        });

        this._value = 0;
        this.connect('repaint', () => this._draw());
    }

    setValue(value) {
        this._value = Math.max(0, Math.min(1, value));
        if (this.mapped)
            this.queue_repaint();
    }

    _draw() {
        const cr = this.get_context();
        const [width, height] = this.get_surface_size();

        // Whole 2px ticks with a 2px gap, same as the conky cards: lit share
        // is the load, the rest is the dim track. Square, no capsule.
        const TICK = 2, GAP = 2;
        const n = Math.floor((width + GAP) / (TICK + GAP));
        const lit = Math.round(n * this._value);
        const {r, g, b} = loadColor(this._value);

        for (let i = 0; i < n; i++) {
            if (i < lit)
                cr.setSourceRGBA(r / RGB_MAX, g / RGB_MAX, b / RGB_MAX, 1);
            else
                cr.setSourceRGBA(42 / 255, 45 / 255, 51 / 255, 1);
            cr.rectangle(i * (TICK + GAP), 0, TICK, height);
            cr.fill();
        }

        cr.$dispose();
    }
});
