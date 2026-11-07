import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {edgeColor, cssColor} from './graph.js';

// Newest sample's weight in the moving average: a one-second spike should
// warm the edges, not flash them.
const SMOOTHING = 0.25;
const STRIP_HEIGHT = 2;
const TRACKED_SIGNALS = ['position-changed', 'size-changed', 'notify::minimized', 'notify::fullscreen'];

/**
 * Machine load shown on the screen edges: a line under the top bar and a strip
 * along the top of the focused window, both on the palette's load ramp. The
 * strip is a shell actor, not a GTK titlebar, so it works for every app
 * (Chrome, Electron, Qt) and updates without the app reloading its theme.
 */
export class HeatGlow {
    constructor() {
        this._heat = 0;
        this._window = null;
        this._windowIds = [];

        this._strip = new St.Widget({reactive: false, visible: false});
        global.window_group.add_child(this._strip);

        // The line under the top bar is its own 2px overlay. Styling
        // Main.panel itself made St recompute the CSS and layout of every
        // widget in the bar once a second, which kept the shell's main
        // thread around 13% busy; restyling one leaf widget costs nothing.
        const box = Main.layoutManager.panelBox;
        this._edge = new St.Widget({reactive: false, height: 2});
        this._edge.add_constraint(new Clutter.BindConstraint({source: box, coordinate: Clutter.BindCoordinate.X}));
        this._edge.add_constraint(new Clutter.BindConstraint({source: box, coordinate: Clutter.BindCoordinate.WIDTH}));
        this._edgeY = new Clutter.BindConstraint({source: box, coordinate: Clutter.BindCoordinate.Y});
        this._edge.add_constraint(this._edgeY);
        Main.layoutManager.uiGroup.add_child(this._edge);
        Main.layoutManager.uiGroup.set_child_above_sibling(this._edge, box);
        this._edgeBinding = box.bind_property('visible', this._edge, 'visible',
            GObject.BindingFlags.SYNC_CREATE);
        this._boxHeightId = box.connect('notify::height', () => this._placeEdge());
        this._edgePx = 1;
        this._placeEdge();

        this._displayIds = [
            global.display.connect('notify::focus-window', () => this._track()),
            global.display.connect('restacked', () => this._raise()),
        ];
        this._overviewIds = [
            Main.overview.connect('showing', () => this._sync()),
            Main.overview.connect('hidden', () => this._sync()),
        ];

        this._track();
        this.update(0);
    }

    /** load: 0..1, the worst of CPU, memory and GPU. */
    update(load) {
        this._heat += (load - this._heat) * SMOOTHING;
        const h = this._heat;
        const c = edgeColor(h);

        this._edgePx = h > 0.75 ? 2 : 1;
        this._placeEdge();
        this._edge.set_style(`background-color: ${cssColor(c, 0.55 + 0.45 * h)};`);
        this._strip.set_style(
            `background-color: ${cssColor(c, 0.6 + 0.4 * h)};` +
            `box-shadow: 0 0 ${Math.round(4 + 12 * h)}px ${cssColor(c, 0.25 + 0.5 * h)};`);
    }

    // Sit on the bar's bottom pixels, where the inset shadow used to be.
    _placeEdge() {
        const box = Main.layoutManager.panelBox;
        this._edge.height = this._edgePx;
        this._edgeY.offset = box.height - this._edgePx;
    }

    _untrack() {
        for (const id of this._windowIds)
            this._window?.disconnect(id);
        this._windowIds = [];
        this._window = null;
    }

    _track() {
        this._untrack();
        const win = global.display.focus_window;
        if (win && win.get_window_type() === Meta.WindowType.NORMAL) {
            this._window = win;
            this._windowIds = TRACKED_SIGNALS.map(s => win.connect(s, () => this._sync()));
            this._windowIds.push(win.connect('unmanaging', () => {
                this._untrack();
                this._sync();
            }));
        }
        this._raise();
        this._sync();
    }

    // Keep the strip directly above the focused window, so windows stacked
    // over it still cover the strip.
    _raise() {
        const actor = this._window?.get_compositor_private();
        const parent = actor?.get_parent();
        if (!parent)
            return;
        if (this._strip.get_parent() !== parent) {
            this._strip.get_parent()?.remove_child(this._strip);
            parent.add_child(this._strip);
        }
        parent.set_child_above_sibling(this._strip, actor);
    }

    _sync() {
        const win = this._window;
        const show = win && !win.minimized && !win.fullscreen && !Main.overview.visible;
        this._strip.visible = Boolean(show);
        if (!show)
            return;
        const r = win.get_frame_rect();
        this._strip.set_position(r.x, r.y);
        this._strip.set_size(r.width, STRIP_HEIGHT);
    }

    destroy() {
        this._untrack();
        for (const id of this._displayIds)
            global.display.disconnect(id);
        for (const id of this._overviewIds)
            Main.overview.disconnect(id);
        Main.layoutManager.panelBox.disconnect(this._boxHeightId);
        this._edgeBinding.unbind();
        this._edge.destroy();
        this._edge = null;
        this._strip.destroy();
        this._strip = null;
    }
}
