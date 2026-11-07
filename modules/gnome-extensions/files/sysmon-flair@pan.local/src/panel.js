import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Sparkline, loadColor, cssColor, tempFraction} from './graph.js';

// 60 samples at one per second gives a minute of visible history.
export const HISTORY_LENGTH = 60;

const SPARK_WIDTH = 56;

// A chip showing a temperature needs room for a second number without
// squeezing the graph that sits behind both. Both widths track the value
// font size: raise one and these have to follow or the digits clip.
const SPARK_WIDTH_WITH_TEMP = 82;

// The chip must state its height explicitly. Inside a BinLayout with nothing
// constraining it vertically, a y_expand DrawingArea will take a square
// allocation and blow out the panel's height. It also has to clear the value
// font's line height, or the overlaid digits are cropped.
const SPARK_HEIGHT = 22;

const percentFmt = new Intl.NumberFormat(undefined, {
    style: 'percent',
    maximumFractionDigits: 0,
});

/** Picks a unit so the number stays short enough for a panel. */
export function formatRate(bytesPerSec) {
    const units = [
        {limit: 1000, suffix: 'B', divisor: 1},
        {limit: 1000 * 1000, suffix: 'K', divisor: 1000},
        {limit: 1000 * 1000 * 1000, suffix: 'M', divisor: 1000 * 1000},
    ];

    const unit = units.find(u => bytesPerSec < u.limit) ??
        {suffix: 'G', divisor: 1000 * 1000 * 1000};

    const value = bytesPerSec / unit.divisor;
    const digits = value < 10 && unit.divisor > 1 ? 1 : 0;

    return `${value.toFixed(digits)}${unit.suffix}`;
}

export function formatBytes(bytes) {
    const GB = 1000 * 1000 * 1000;
    return `${(bytes / GB).toFixed(1)} GB`;
}

export function formatUptime(seconds) {
    const d = Math.floor(seconds / 86400);
    const h = Math.floor((seconds % 86400) / 3600);
    const m = Math.floor((seconds % 3600) / 60);

    return d > 0 ? `${d}d ${h}h ${m}m` : `${h}h ${m}m`;
}

const GIB = 1024 * 1024 * 1024;

/** "8.1/62G": used keeps a decimal while small, so idle VRAM still moves. */
export function formatUsage(usedBytes, totalBytes) {
    const used = usedBytes / GIB;
    const digits = used < 10 ? 1 : 0;
    return `${used.toFixed(digits)}/${Math.round(totalBytes / GIB)}G`;
}

export {percentFmt};

/**
 * Single-letter tag in front of a chip. Four chips side by side are no longer
 * identifiable by position alone.
 */
export function tagged(tag, chip) {
    const box = new St.BoxLayout({style_class: 'sysmon-stat'});

    box.add_child(new St.Label({
        text: tag,
        style_class: 'sysmon-chip-tag',
        y_align: Clutter.ActorAlign.CENTER,
    }));
    box.add_child(chip);

    return box;
}

/**
 * One panel stat: a minute of rolling history with the current value sitting
 * on top of it.
 *
 * The graph and the number occupy the same cell rather than sitting side by
 * side, which buys the graph roughly twice the width in the same footprint.
 * Clutter.BinLayout is what allows that: unlike a BoxLayout it stacks its
 * children instead of placing them in a row.
 *
 * The number stays a real St.Label rather than Cairo text, so it renders
 * through Pango with the shell's own font and matches every other label in
 * the panel. Cairo's text API would not.
 */
export const StatChip = GObject.registerClass(
class StatChip extends St.Widget {
    constructor({accessibleName, withTemp = false, width}) {
        width ??= withTemp ? SPARK_WIDTH_WITH_TEMP : SPARK_WIDTH;

        super({
            style_class: 'sysmon-chip',
            layout_manager: new Clutter.BinLayout(),
            accessible_name: accessibleName,
            width,
            height: SPARK_HEIGHT,
            y_align: Clutter.ActorAlign.CENTER,
        });

        this._spark = new Sparkline({
            capacity: HISTORY_LENGTH,
            width,
            styleClass: 'sysmon-chip-spark',
        });
        this._spark.height = SPARK_HEIGHT;
        this.add_child(this._spark);

        // Temperature sits at the leading edge, load at the trailing edge, both
        // over the same graph. Two numbers reading inward from the ends stay
        // distinguishable at a glance in a way two adjacent numbers would not.
        if (withTemp) {
            this._temp = new St.Label({
                style_class: 'sysmon-chip-temp',
                x_align: Clutter.ActorAlign.START,
                y_align: Clutter.ActorAlign.CENTER,
                x_expand: true,
                visible: false,
            });
            this.add_child(this._temp);
        }

        this._value = new St.Label({
            style_class: 'sysmon-chip-value',
            x_align: Clutter.ActorAlign.END,
            y_align: Clutter.ActorAlign.CENTER,
            x_expand: true,
        });
        this.add_child(this._value);
    }

    /** load drives the graph and colour; text overrides the shown value. */
    update(load, text = percentFmt.format(load)) {
        this._spark.push(load);

        this._value.text = text;
        this._value.set_style(`color: ${cssColor(loadColor(load))};`);
    }

    /**
     * Temperature carries its own colour scale, not the load ramp. A chip at
     * 95% load running cool must not paint its temperature red, and one
     * throttling at idle must not paint it green.
     */
    setTemp(celsius) {
        if (!this._temp)
            return;

        this._temp.visible = celsius !== null && celsius !== undefined;

        if (!this._temp.visible)
            return;

        this._temp.text = `${Math.round(celsius)}\u00b0`;
        this._temp.set_style(
            `color: ${cssColor(loadColor(tempFraction(celsius)))};`);
    }
});
