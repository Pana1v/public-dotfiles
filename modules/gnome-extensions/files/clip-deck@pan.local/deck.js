// The deck: a keyboard-first clipboard card in the conky language.
//
//   01 CLIPBOARD                                 48 CLIPS / 12 IMAGES
//   > search
//   ALL 48   TEXT 30   IMAGES 12   LINKS 4   PINNED 2
//   . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
//   01 [thumb] IMAGE 1920 X 1080      2M | <large preview of the
//   02  PATH   /tmp/claude-1000/...   5M |  selected clip, with its
//   03  #ff1f3d (swatch)              9M |  size, type and age>
//   . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
//   ENTER paste   ALT+1..9 paste nth   CTRL+P pin   SHIFT+DEL forget
import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {ensureActorVisibleInScrollView} from 'resource:///org/gnome/shell/misc/animationUtils.js';

import {Store} from './store.js';

const MAX_ROWS = 150;

const TABS = [
    ['all', 'ALL', () => true],
    ['text', 'TEXT', i => i.kind === 'text'],
    ['image', 'IMAGES', i => i.kind === 'image'],
    ['link', 'LINKS', i => i.type === 'url' || i.type === 'path'],
    ['pinned', 'PINNED', i => i.pinned],
];

const TAG = {text: 'TXT', code: 'CODE', url: 'URL', path: 'PATH', hex: 'HEX', image: 'IMG'};

export function age(t) {
    const s = (Date.now() - t) / 1000;
    if (s < 60)
        return 'NOW';
    if (s < 3600)
        return `${Math.floor(s / 60)}M`;
    if (s < 86400)
        return `${Math.floor(s / 3600)}H`;
    return `${Math.floor(s / 86400)}D`;
}

function bytesLabel(n) {
    if (n < 1024)
        return `${n} B`;
    if (n < 1024 * 1024)
        return `${(n / 1024).toFixed(0)} KB`;
    return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

function oneLine(text) {
    return text.replace(/\s+/g, ' ').trim().slice(0, 200);
}

function label(text, styleClass, {ellipsize = Pango.EllipsizeMode.NONE, ...props} = {}) {
    const l = new St.Label({text, style_class: styleClass, y_align: Clutter.ActorAlign.CENTER, ...props});
    l.clutter_text.ellipsize = ellipsize;
    return l;
}

/** Conky hairline: a row of real dots. Colour comes from the CSS `color`. */
const DotRule = GObject.registerClass(
class DotRule extends St.DrawingArea {
    constructor() {
        super({style_class: 'cd-rule', x_expand: true, height: 4});
    }

    vfunc_repaint() {
        const cr = this.get_context();
        const [w, h] = this.get_surface_size();
        const c = this.get_theme_node().get_foreground_color();
        cr.setSourceRGBA(c.red / 255, c.green / 255, c.blue / 255, c.alpha / 255);
        for (let x = 1.5; x < w; x += 4) {
            cr.newSubPath();
            cr.arc(x, h / 2, 0.8, 0, 2 * Math.PI);
        }
        cr.fill();
        cr.$dispose();
    }
});

export class Deck {
    constructor(store, onChoose) {
        this._store = store;
        this._onChoose = onChoose;
        this._tab = 0;
        this._sel = 0;
        this._shown = [];
        this._rows = [];
        this._grab = null;
        this._build();
    }

    destroy() {
        this.close();
        this._backdrop.destroy();
        this._backdrop = null;
    }

    get isOpen() {
        return this._grab !== null;
    }

    // ── Build ────────────────────────────────────────────────────────────

    _build() {
        this._backdrop = new St.Widget({
            style_class: 'cd-backdrop',
            reactive: true,
            visible: false,
            layout_manager: new Clutter.BinLayout(),
        });
        this._backdrop.connect('button-press-event', () => {
            this.close();
            return Clutter.EVENT_STOP;
        });
        Main.layoutManager.addTopChrome(this._backdrop);

        this._card = new St.BoxLayout({
            style_class: 'clip-deck',
            orientation: Clutter.Orientation.VERTICAL,
            reactive: true,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
        });
        // Clicks inside the card must not reach the backdrop.
        this._card.connect('button-press-event', () => Clutter.EVENT_STOP);
        this._backdrop.add_child(this._card);

        // Header: 01 CLIPBOARD ............ status
        const header = new St.BoxLayout({style_class: 'cd-header'});
        header.add_child(label('01', 'cd-no'));
        header.add_child(label('CLIPBOARD', 'cd-title', {x_expand: true}));
        this._status = label('', 'cd-status');
        header.add_child(this._status);
        this._card.add_child(header);

        // Search line
        const search = new St.BoxLayout({style_class: 'cd-search'});
        search.add_child(label('\u{f0142}', 'cd-caret'));
        this._entry = new St.Entry({style_class: 'cd-entry', hint_text: 'search', x_expand: true, can_focus: true});
        this._entry.clutter_text.connect('text-changed', () => {
            this._sel = 0;
            this._refilter();
        });
        this._entry.clutter_text.connect('key-press-event', (_a, event) => this._onKey(event));
        search.add_child(this._entry);
        this._card.add_child(search);

        // Filter tabs
        this._tabBox = new St.BoxLayout({style_class: 'cd-tabs'});
        this._tabButtons = TABS.map(([, name], i) => {
            const box = new St.BoxLayout({style_class: 'cd-tab-box'});
            box.add_child(label(name, 'cd-tab-name'));
            const count = label('0', 'cd-tab-count');
            box.add_child(count);
            const button = new St.Button({style_class: 'cd-tab', child: box, can_focus: false});
            button.connect('clicked', () => this._setTab(i));
            button._count = count;
            this._tabBox.add_child(button);
            return button;
        });
        this._card.add_child(this._tabBox);
        this._card.add_child(new DotRule());

        // Body: list | preview
        const body = new St.BoxLayout({style_class: 'cd-body', y_expand: true});
        this._list = new St.BoxLayout({style_class: 'cd-list', orientation: Clutter.Orientation.VERTICAL});
        this._scroll = new St.ScrollView({
            style_class: 'cd-list-scroll',
            hscrollbar_policy: St.PolicyType.NEVER,
            vscrollbar_policy: St.PolicyType.AUTOMATIC,
            overlay_scrollbars: true,
            x_expand: false,
            child: this._list,
        });
        body.add_child(this._scroll);

        this._preview = new St.BoxLayout({
            style_class: 'cd-preview',
            orientation: Clutter.Orientation.VERTICAL,
            x_expand: true,
        });
        this._previewMeta = label('', 'cd-preview-meta');
        this._preview.add_child(this._previewMeta);
        this._previewBody = new St.BoxLayout({
            style_class: 'cd-preview-body',
            orientation: Clutter.Orientation.VERTICAL,
            x_expand: true,
            y_expand: true,
        });
        this._preview.add_child(this._previewBody);
        body.add_child(this._preview);
        this._card.add_child(body);

        this._card.add_child(new DotRule());

        // Key hints
        const hints = new St.BoxLayout({style_class: 'cd-hints'});
        for (const [key, what] of [['ENTER', 'paste'], ['ALT+1..9', 'paste nth'], ['CTRL+ENTER', 'copy'],
            ['CTRL+P', 'pin'], ['SHIFT+DEL', 'forget'], ['TAB', 'filter'], ['ESC', 'close']]) {
            const h = new St.BoxLayout({style_class: 'cd-hint'});
            h.add_child(label(key, 'cd-hint-key'));
            h.add_child(label(what, 'cd-hint-what'));
            hints.add_child(h);
        }
        this._card.add_child(hints);
    }

    // ── Open / close ─────────────────────────────────────────────────────

    open() {
        if (this.isOpen)
            return;
        const m = Main.layoutManager.currentMonitor;
        this._backdrop.set_position(m.x, m.y);
        this._backdrop.set_size(m.width, m.height);
        this._backdrop.show();

        this._grab = Main.pushModal(this._backdrop, {actionMode: Shell.ActionMode.SYSTEM_MODAL});
        this._entry.text = '';
        this._sel = 0;
        this._refilter();
        global.stage.set_key_focus(this._entry);
    }

    close() {
        if (!this._grab)
            return;
        Main.popModal(this._grab);
        this._grab = null;
        this._backdrop.hide();
    }

    toggle() {
        if (this.isOpen)
            this.close();
        else
            this.open();
    }

    /** New clip arrived while open: keep the view current. */
    refresh() {
        if (this.isOpen)
            this._refilter();
    }

    // ── Filtering and rows ───────────────────────────────────────────────

    _matches(item, terms) {
        if (!terms.length)
            return true;
        const hay = item.kind === 'image'
            ? `image img ${item.mime} ${item.w}x${item.h}`
            : `${item.type} ${item.text}`.toLowerCase();
        return terms.every(t => hay.includes(t));
    }

    _refilter() {
        const items = this._store.items;
        const terms = this._entry.text.toLowerCase().split(/\s+/).filter(Boolean);
        const searched = items.filter(i => this._matches(i, terms));

        TABS.forEach(([, , test], i) => {
            this._tabButtons[i]._count.text = String(searched.filter(test).length);
            this._tabButtons[i].checked = i === this._tab;
        });

        const test = TABS[this._tab][2];
        const list = searched.filter(test);
        // Pinned first, then newest.
        this._shown = [...list.filter(i => i.pinned), ...list.filter(i => !i.pinned)].slice(0, MAX_ROWS);
        this._sel = Math.max(0, Math.min(this._sel, this._shown.length - 1));

        const images = items.filter(i => i.kind === 'image').length;
        this._status.text = `${items.length} CLIPS / ${images} IMAGES`;

        this._list.destroy_all_children();
        this._rows = this._shown.map((item, i) => this._row(item, i));
        this._rows.forEach(r => this._list.add_child(r));
        if (!this._shown.length)
            this._list.add_child(label(items.length ? 'no match' : 'nothing copied yet', 'cd-empty'));
        this._select(this._sel, true);
    }

    _row(item, i) {
        const box = new St.BoxLayout({style_class: 'cd-row-box', x_expand: true});
        box.add_child(label(String(i + 1).padStart(2, '0'), 'cd-idx'));

        if (item.kind === 'image') {
            box.add_child(new St.Widget({
                style_class: 'cd-thumb',
                style: `background-image: url("${Store.uri(item.file)}");`,
                y_align: Clutter.ActorAlign.CENTER,
            }));
        } else if (item.type === 'hex') {
            box.add_child(new St.Widget({
                style_class: 'cd-swatch',
                style: `background-color: ${item.text.trim()};`,
                y_align: Clutter.ActorAlign.CENTER,
            }));
        } else {
            box.add_child(label(TAG[item.type] ?? 'TXT', 'cd-tag'));
        }

        const text = item.kind === 'image'
            ? (item.w ? `${item.w} x ${item.h}` : item.mime.replace('image/', '').toUpperCase())
            : oneLine(item.text);
        box.add_child(label(text, 'cd-row-text', {x_expand: true, ellipsize: Pango.EllipsizeMode.END}));

        if (item.pinned)
            box.add_child(new St.Widget({style_class: 'cd-pin', y_align: Clutter.ActorAlign.CENTER}));
        box.add_child(label(age(item.t), 'cd-age'));

        const row = new St.Button({style_class: 'cd-row', child: box, x_expand: true, can_focus: false, track_hover: true});
        row.connect('clicked', () => this._choose(i, true));
        row.connect('notify::hover', () => {
            if (row.hover)
                this._select(i, false);
        });
        return row;
    }

    _select(i, scroll) {
        this._rows[this._sel]?.remove_style_pseudo_class('selected');
        this._sel = i;
        const row = this._rows[i];
        if (row) {
            row.add_style_pseudo_class('selected');
            if (scroll)
                ensureActorVisibleInScrollView(this._scroll, row);
        }
        this._showPreview(this._shown[i]);
    }

    _setTab(i) {
        this._tab = (i + TABS.length) % TABS.length;
        this._sel = 0;
        this._refilter();
    }

    // ── Preview ──────────────────────────────────────────────────────────

    _showPreview(item) {
        this._previewBody.destroy_all_children();
        if (!item) {
            this._previewMeta.text = '';
            return;
        }
        const when = age(item.t) === 'NOW' ? 'JUST NOW' : `${age(item.t)} AGO`;
        if (item.kind === 'image') {
            const dims = item.w ? `${item.w} X ${item.h}` : '';
            const fmt = item.mime.replace('image/', '').toUpperCase();
            this._previewMeta.text = [dims, fmt, bytesLabel(item.bytes), when].filter(Boolean).join('   ');
            this._previewBody.add_child(new St.Widget({
                style_class: 'cd-preview-image',
                style: `background-image: url("${Store.uri(item.file)}");`,
                x_expand: true,
                y_expand: true,
            }));
            return;
        }

        const lines = item.text.split('\n').length;
        this._previewMeta.text = [TAG[item.type] ?? 'TXT', `${item.text.length} CHARS`,
            lines > 1 ? `${lines} LINES` : '', when].filter(Boolean).join('   ');

        if (item.type === 'hex') {
            const box = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'cd-hex', y_expand: true});
            box.add_child(new St.Widget({
                style_class: 'cd-hex-swatch',
                style: `background-color: ${item.text.trim()};`,
                x_expand: true,
                y_expand: true,
            }));
            box.add_child(label(item.text.trim().toLowerCase(), 'cd-hex-value'));
            this._previewBody.add_child(box);
            return;
        }

        const body = label(item.text.slice(0, 6000), item.type === 'code' ? 'cd-preview-text cd-code' : 'cd-preview-text');
        body.clutter_text.line_wrap = true;
        body.clutter_text.line_wrap_mode = Pango.WrapMode.WORD_CHAR;
        body.y_align = Clutter.ActorAlign.START;
        const scroll = new St.ScrollView({
            style_class: 'cd-preview-scroll',
            x_expand: true,
            y_expand: true,
            hscrollbar_policy: St.PolicyType.NEVER,
            overlay_scrollbars: true,
            child: new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true}),
        });
        scroll.child.add_child(body);
        this._previewBody.add_child(scroll);
    }

    // ── Keys ─────────────────────────────────────────────────────────────

    _choose(i, paste) {
        const item = this._shown[i];
        if (!item)
            return;
        this.close();
        this._onChoose(item, paste);
    }

    _onKey(event) {
        const key = event.get_key_symbol();
        const mods = event.get_state();
        const ctrl = (mods & Clutter.ModifierType.CONTROL_MASK) !== 0;
        const shift = (mods & Clutter.ModifierType.SHIFT_MASK) !== 0;
        const alt = (mods & Clutter.ModifierType.MOD1_MASK) !== 0;
        const n = this._shown.length;

        if (alt && key >= Clutter.KEY_1 && key <= Clutter.KEY_9) {
            this._choose(key - Clutter.KEY_1, true);
            return Clutter.EVENT_STOP;
        }

        switch (key) {
        case Clutter.KEY_Escape:
            this.close();
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Down:
            if (n)
                this._select((this._sel + 1) % n, true);
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Up:
            if (n)
                this._select((this._sel - 1 + n) % n, true);
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Page_Down:
            if (n)
                this._select(Math.min(n - 1, this._sel + 8), true);
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Page_Up:
            if (n)
                this._select(Math.max(0, this._sel - 8), true);
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Tab:
            this._setTab(this._tab + 1);
            return Clutter.EVENT_STOP;
        case Clutter.KEY_ISO_Left_Tab:
            this._setTab(this._tab - 1);
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Return:
        case Clutter.KEY_KP_Enter:
            this._choose(this._sel, !ctrl);
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Delete:
            if (!shift)
                return Clutter.EVENT_PROPAGATE;
            if (ctrl)
                this._store.clearLoose();
            else if (this._shown[this._sel])
                this._store.remove(this._shown[this._sel]);
            this._refilter();
            return Clutter.EVENT_STOP;
        case Clutter.KEY_p:
        case Clutter.KEY_P:
            if (!ctrl)
                return Clutter.EVENT_PROPAGATE;
            if (this._shown[this._sel]) {
                const item = this._shown[this._sel];
                this._store.togglePin(item);
                this._refilter();
                this._select(Math.max(0, this._shown.indexOf(item)), true);
            }
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }
}
