import Cairo from 'cairo';
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';
import St from 'gi://St';

const ART_SIZE = 26;
const BAR_COUNT = 24;
const VIZ_WIDTH = 70;

// Marquee timing. Text that scrolls the instant it appears reads as jittery,
// so we hold each end still before moving.
const SCROLL_PX_PER_SEC = 26;
const SCROLL_HOLD_MS = 1400;

const PROGRESS_TICK_MS = 500;
const PROGRESS_HEIGHT = 2;

const FALLBACK_ACCENT = {r: 128, g: 222, b: 156};

/** Clipped label that scrolls horizontally only when its text overflows. */
const Marquee = GObject.registerClass(
class Marquee extends St.BoxLayout {
    constructor(styleClass) {
        super({
            style_class: styleClass,
            clip_to_allocation: true,
            x_expand: false,
        });

        this._label = new St.Label({
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._label.clutter_text.set({
            ellipsize: Pango.EllipsizeMode.NONE,   // we scroll instead of truncating
            single_line_mode: true,
        });
        this.add_child(this._label);

        this._timeoutId = 0;
        this._text = '';
        this._lastWidth = -1;

        this.connect('destroy', () => this._stop());

        // Allocation notifies fire constantly during panel layout; restarting
        // the scroll on every one of them would thrash the timer and reset the
        // animation mid-travel. Only a real width change matters.
        this.connect('notify::allocation', () => {
            const width = this.allocation.get_width();
            if (width === this._lastWidth)
                return;

            this._lastWidth = width;
            this._restart();
        });
    }

    setText(text) {
        if (text === this._text)
            return;

        this._text = text;
        this._label.text = text;
        this._restart();
    }

    _stop() {
        if (this._timeoutId)
            GLib.source_remove(this._timeoutId);
        this._timeoutId = 0;

        this._label.remove_all_transitions();
    }

    _restart() {
        this._stop();
        this._label.translation_x = 0;

        // Defer: during allocation the widths are not settled yet.
        this._timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 60, () => {
            this._timeoutId = 0;
            this._maybeScroll();
            return GLib.SOURCE_REMOVE;
        });
    }

    _maybeScroll() {
        const visible = this.allocation.get_width();
        const needed = this._label.get_preferred_width(-1)[1];
        const overflow = needed - visible;

        if (overflow <= 1 || visible <= 1)
            return;

        this._scrollTo(-overflow, overflow);
    }

    _scrollTo(target, distance) {
        if (!this.mapped)
            return;

        this._label.ease({
            translation_x: target,
            duration: (distance / SCROLL_PX_PER_SEC) * 1000,
            delay: SCROLL_HOLD_MS,
            mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
            onComplete: () => {
                const next = target === 0 ? -distance : 0;
                this._scrollTo(next, distance);
            },
        });
    }
});

/** Cairo-drawn spectrum bars. */
const Spectrum = GObject.registerClass(
class Spectrum extends St.DrawingArea {
    constructor() {
        super({
            style_class: 'spotify-deck-spectrum',
            width: VIZ_WIDTH,
            y_expand: true,
        });

        this._bars = new Array(BAR_COUNT).fill(0);
        this._accent = FALLBACK_ACCENT;

        this.connect('repaint', () => this._draw());
    }

    setBars(bars) {
        this._bars = bars;

        // Repainting only while mapped avoids burning work behind a hidden
        // panel or on an inactive workspace.
        if (this.mapped)
            this.queue_repaint();
    }

    setAccent(accent) {
        this._accent = accent ?? FALLBACK_ACCENT;
        if (this.mapped)
            this.queue_repaint();
    }

    _draw() {
        const cr = this.get_context();
        const [width, height] = this.get_surface_size();

        const count = this._bars.length;
        const slot = width / count;
        const barWidth = Math.max(1, slot * 0.58);
        const radius = barWidth / 2;

        const {r, g, b} = this._accent;
        const baseR = r / 255, baseG = g / 255, baseB = b / 255;

        // One gradient reused across every bar: the tip is brighter than the
        // base, which reads as light falling on the bars rather than as flat
        // blocks of colour.
        const gradient = new Cairo.LinearGradient(0, 0, 0, height);
        gradient.addColorStopRGBA(0, Math.min(1, baseR * 1.35 + 0.12),
            Math.min(1, baseG * 1.35 + 0.12),
            Math.min(1, baseB * 1.35 + 0.12), 1.0);
        gradient.addColorStopRGBA(1, baseR * 0.85, baseG * 0.85, baseB * 0.85, 0.72);

        for (let i = 0; i < count; i++) {
            const value = Math.max(0, Math.min(1, this._bars[i]));

            // A visible floor keeps the widget looking alive during quiet
            // passages instead of collapsing to an empty rectangle.
            const barHeight = Math.max(2, value * height);

            const x = i * slot + (slot - barWidth) / 2;
            const y = height - barHeight;

            this._roundedBar(cr, x, y, barWidth, barHeight, radius);

            cr.setSource(gradient);
            cr.fillPreserve();

            // Quiet bars fade back rather than disappearing, so the row keeps
            // its shape between beats.
            cr.setSourceRGBA(0, 0, 0, 0.35 * (1 - value));
            cr.fill();
        }

        cr.$dispose();
    }

    _roundedBar(cr, x, y, w, h, r) {
        const rr = Math.min(r, h / 2);

        cr.newSubPath();
        cr.arc(x + w - rr, y + rr, rr, -Math.PI / 2, 0);
        cr.arc(x + w - rr, y + h - rr, rr, 0, Math.PI / 2);
        cr.arc(x + rr, y + h - rr, rr, Math.PI / 2, Math.PI);
        cr.arc(x + rr, y + rr, rr, Math.PI, 1.5 * Math.PI);
        cr.closePath();
    }
});

/**
 * The always-visible taskbar strip: cover, scrolling track text, live
 * spectrum, a hairline progress underline, and transport controls that
 * reveal on hover.
 */
export const DeckStrip = GObject.registerClass({
    Signals: {
        'control': {param_types: [GObject.TYPE_STRING]},
    },
}, class DeckStrip extends St.Widget {
    static get BAR_COUNT() {
        return BAR_COUNT;
    }

    constructor() {
        // Vertical: the progress bar sits under the row, in the cross axis, so
        // its width never adds to the strip's width.
        super({
            style_class: 'spotify-deck-strip',
            reactive: true,
            track_hover: true,
            layout_manager: new Clutter.BoxLayout({
                orientation: Clutter.Orientation.VERTICAL,
            }),
        });

        this._row = new St.BoxLayout({
            style_class: 'spotify-deck-row',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this._row);

        this._buildArt();
        this._buildText();
        this._buildSpectrum();
        this._buildControls();
        this._buildProgress();

        this._progressId = 0;
        this._positionFn = null;

        this.connect('notify::hover', () => this._syncHover());
        this.connect('destroy', () => this._onDestroy());
    }

    _buildArt() {
        this._art = new St.Widget({
            style_class: 'spotify-deck-art',
            width: ART_SIZE,
            height: ART_SIZE,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._row.add_child(this._art);
    }

    _buildText() {
        this._textBox = new St.BoxLayout({
            style_class: 'spotify-deck-text',
            vertical: true,
            y_align: Clutter.ActorAlign.CENTER,
        });

        this._title = new Marquee('spotify-deck-title');
        this._artist = new Marquee('spotify-deck-artist');

        this._textBox.add_child(this._title);
        this._textBox.add_child(this._artist);
        this._row.add_child(this._textBox);
    }

    _buildSpectrum() {
        this._spectrum = new Spectrum();
        this._row.add_child(this._spectrum);
    }

    _buildControls() {
        this._controls = new St.BoxLayout({
            style_class: 'spotify-deck-controls',
            y_align: Clutter.ActorAlign.CENTER,
            opacity: 0,
            visible: false,
        });

        this._prevBtn = this._makeButton('media-skip-backward-symbolic', 'previous');
        this._playBtn = this._makeButton('media-playback-start-symbolic', 'playpause');
        this._nextBtn = this._makeButton('media-skip-forward-symbolic', 'next');

        [this._prevBtn, this._playBtn, this._nextBtn]
            .forEach(b => this._controls.add_child(b));

        this._row.add_child(this._controls);
    }

    _makeButton(iconName, action) {
        const button = new St.Button({
            style_class: 'spotify-deck-button',
            child: new St.Icon({
                icon_name: iconName,
                style_class: 'spotify-deck-button-icon',
            }),
        });

        button.connect('clicked', () => {
            this.emit('control', action);
            return Clutter.EVENT_STOP;
        });

        return button;
    }

    _buildProgress() {
        this._progress = new St.Widget({
            style_class: 'spotify-deck-progress',
            x_align: Clutter.ActorAlign.START,
            height: PROGRESS_HEIGHT,
        });
        this.add_child(this._progress);

        this._row.connect('notify::allocation', () => this._layoutProgress());
    }

    /**
     * Width comes from the content row, never from this actor: measuring the
     * container we are resizing would feed the value back into its own input.
     * The clamp is a second guard on the same hazard.
     */
    _layoutProgress() {
        const track = this._row.allocation.get_width();
        if (track <= 0)
            return;

        const filled = Math.round(track * this._fraction());
        this._progress.width = Math.max(0, Math.min(track, filled));
    }

    _fraction() {
        if (!this._positionFn)
            return 0;

        const {position, length} = this._positionFn();
        if (!length || length <= 0)
            return 0;

        return Math.max(0, Math.min(1, position / length));
    }

    _syncHover() {
        const show = this.hover;

        if (show)
            this._controls.show();

        this._controls.ease({
            opacity: show ? 255 : 0,
            duration: 160,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            onComplete: () => {
                if (!this.hover)
                    this._controls.hide();
            },
        });
    }

    // --- public API --------------------------------------------------------

    setTrack({title, artist}) {
        this._title.setText(title || 'Nothing playing');
        this._artist.setText(artist || '');
        this._artist.visible = !!artist;
    }

    setArtPath(path) {
        this._art.set_style(path
            ? `background-image: url("file://${path}");`
            : null);

        this._art.visible = !!path;
    }

    setAccent(accent) {
        this._spectrum.setAccent(accent);

        const {r, g, b} = accent ?? FALLBACK_ACCENT;
        this._progress.set_style(`background-color: rgba(${r},${g},${b},0.95);`);
    }

    setBars(bars) {
        this._spectrum.setBars(bars);
    }

    setPlaying(playing) {
        this._playBtn.child.icon_name = playing
            ? 'media-playback-pause-symbolic'
            : 'media-playback-start-symbolic';
    }

    setCanSkip({next, previous}) {
        this._nextBtn.reactive = next;
        this._prevBtn.reactive = previous;
        this._nextBtn.opacity = next ? 255 : 100;
        this._prevBtn.opacity = previous ? 255 : 100;
    }

    /** positionFn returns {position, length} in seconds. */
    trackProgress(positionFn) {
        this._positionFn = positionFn;

        if (this._progressId)
            return;

        this._progressId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT, PROGRESS_TICK_MS, () => {
                this._layoutProgress();
                return GLib.SOURCE_CONTINUE;
            });
    }

    _onDestroy() {
        if (this._progressId)
            GLib.source_remove(this._progressId);
        this._progressId = 0;
    }
});
