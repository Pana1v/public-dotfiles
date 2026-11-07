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

    _draw() {
        const cr = this.get_context();
        const [width, height] = this.get_surface_size();
        const values = this._ordered();

        if (values.length < 2) {
            cr.$dispose();
            return;
        }

        const color = this._colorFn(this.latest);
        const {r, g, b} = color;
        const step = width / (this._capacity - 1);

        // The chart is anchored to the right so the newest sample sits at the
        // leading edge and history scrolls away behind it.
        const offset = width - (values.length - 1) * step;
        const pointY = v => height - v * (height - 1) - 0.5;

        cr.moveTo(offset, height);
        values.forEach((v, i) => cr.lineTo(offset + i * step, pointY(v)));
        cr.lineTo(offset + (values.length - 1) * step, height);
        cr.closePath();

        // A vertical gradient rather than a flat wash: dense at the baseline,
        // fading upward. The graph is the main visual in the panel now, so a
        // uniform 24% fill would read as a grey smear.
        const fill = new Cairo.LinearGradient(0, 0, 0, height);
        fill.addColorStopRGBA(0, r / RGB_MAX, g / RGB_MAX, b / RGB_MAX, 0.04);
        fill.addColorStopRGBA(1, r / RGB_MAX, g / RGB_MAX, b / RGB_MAX, 0.28);

        cr.setSource(fill);
        cr.fill();

        cr.moveTo(offset, pointY(values[0]));
        values.forEach((v, i) => cr.lineTo(offset + i * step, pointY(v)));

        cr.setLineWidth(1.25);
        cr.setLineJoin(Cairo.LineJoin.MITER);
        cr.setLineCap(Cairo.LineCap.BUTT);
        cr.setSourceRGBA(r / RGB_MAX, g / RGB_MAX, b / RGB_MAX, 0.95);
        cr.stroke();

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
