import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';

const MPRIS_PREFIX = 'org.mpris.MediaPlayer2.';
const PLAYER_IFACE = 'org.mpris.MediaPlayer2.Player';
const OBJECT_PATH = '/org/mpris/MediaPlayer2';
const PROPS_IFACE = 'org.freedesktop.DBus.Properties';

// Spotify reports track length in microseconds.
const USEC_PER_SEC = 1000000;

// Spotify never emits PropertiesChanged for Position, so a progress bar driven
// purely off D-Bus looks frozen. We interpolate locally and re-sync from the
// real Position on this interval to correct for drift and unreported seeks.
const RESYNC_INTERVAL_SEC = 10;

/**
 * Wraps one MPRIS player on the session bus and normalises its quirks into a
 * plain, always-valid state object.
 */
export const MprisPlayer = GObject.registerClass({
    Signals: {
        'changed': {},
        'closed': {},
    },
}, class MprisPlayer extends GObject.Object {
    constructor(busName) {
        super();

        this._busName = busName;
        this._cancellable = new Gio.Cancellable();

        this.status = 'Stopped';
        this.title = '';
        this.artist = '';
        this.album = '';
        this.artUrl = '';
        this.trackId = '';
        this.lengthSec = 0;
        this.canGoNext = false;
        this.canGoPrevious = false;

        // Local playback-position model: position at the moment we last synced,
        // plus the monotonic clock reading at that moment.
        this._basePositionSec = 0;
        this._baseClockUsec = GLib.get_monotonic_time();
        this._resyncId = 0;

        this._proxy = null;
        this._buildProxy();
    }

    _buildProxy() {
        Gio.DBusProxy.new(
            Gio.DBus.session,
            Gio.DBusProxyFlags.NONE,
            null,
            this._busName,
            OBJECT_PATH,
            PLAYER_IFACE,
            this._cancellable,
            (src, res) => {
                try {
                    this._proxy = Gio.DBusProxy.new_finish(res);
                } catch (e) {
                    if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        logError(e, 'spotify-deck: MPRIS proxy failed');
                    return;
                }

                this._propsId = this._proxy.connect('g-properties-changed',
                    () => this._readProxyState());

                this._readProxyState();
                this._ensureResync();
            });
    }

    _readProxyState() {
        if (!this._proxy)
            return;

        const status = this._proxy.get_cached_property('PlaybackStatus');
        this.status = status ? status.unpack() : 'Stopped';

        this.canGoNext = this._unpackBool('CanGoNext');
        this.canGoPrevious = this._unpackBool('CanGoPrevious');

        const metaVariant = this._proxy.get_cached_property('Metadata');
        const meta = metaVariant ? metaVariant.deepUnpack() : {};

        const prevTrackId = this.trackId;

        this.trackId = this._metaString(meta, 'mpris:trackid');
        this.title = this._metaString(meta, 'xesam:title');
        this.album = this._metaString(meta, 'xesam:album');
        this.artUrl = this._metaString(meta, 'mpris:artUrl');

        // xesam:artist is an array of strings; join for display.
        const artists = meta['xesam:artist'];
        this.artist = artists ? artists.deepUnpack().join(', ') : '';

        const length = meta['mpris:length'];
        this.lengthSec = length ? Number(length.deepUnpack()) / USEC_PER_SEC : 0;

        // A new track resets our local position model immediately rather than
        // waiting for the next resync tick.
        if (this.trackId !== prevTrackId)
            this._syncPosition();

        this.emit('changed');
    }

    _unpackBool(name) {
        const v = this._proxy.get_cached_property(name);
        return v ? v.unpack() : false;
    }

    _metaString(meta, key) {
        const v = meta[key];
        if (!v)
            return '';
        const s = v.deepUnpack();
        return typeof s === 'string' ? s : '';
    }

    get isPlaying() {
        return this.status === 'Playing';
    }

    /** Interpolated playback position in seconds. */
    get positionSec() {
        if (!this.isPlaying)
            return this._basePositionSec;

        const elapsed =
            (GLib.get_monotonic_time() - this._baseClockUsec) / USEC_PER_SEC;
        const pos = this._basePositionSec + elapsed;

        return this.lengthSec > 0 ? Math.min(pos, this.lengthSec) : pos;
    }

    _ensureResync() {
        if (this._resyncId)
            return;

        this._resyncId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, RESYNC_INTERVAL_SEC, () => {
                this._syncPosition();
                return GLib.SOURCE_CONTINUE;
            });
    }

    /**
     * Position is a plain D-Bus property, not exposed on the Player proxy's
     * cached set reliably, so we read it explicitly via Properties.Get.
     */
    _syncPosition() {
        Gio.DBus.session.call(
            this._busName, OBJECT_PATH, PROPS_IFACE, 'Get',
            new GLib.Variant('(ss)', [PLAYER_IFACE, 'Position']),
            new GLib.VariantType('(v)'), Gio.DBusCallFlags.NONE, -1,
            this._cancellable,
            (bus, res) => {
                try {
                    const [boxed] = bus.call_finish(res).deepUnpack();
                    this._basePositionSec = Number(boxed.deepUnpack()) / USEC_PER_SEC;
                    this._baseClockUsec = GLib.get_monotonic_time();
                } catch (e) {
                    // Some players refuse Position entirely; the interpolated
                    // value stays usable, so this is not worth logging loudly.
                }
            });
    }

    _invoke(method) {
        if (!this._proxy)
            return;

        this._proxy.call(method, null, Gio.DBusCallFlags.NONE, -1,
            this._cancellable, (p, res) => {
                try {
                    p.call_finish(res);
                } catch (e) {
                    logError(e, `spotify-deck: ${method} failed`);
                }
            });
    }

    playPause() {
        this._invoke('PlayPause');
    }

    next() {
        this._invoke('Next');
        this._syncPosition();
    }

    previous() {
        this._invoke('Previous');
        this._syncPosition();
    }

    /** Seek to an absolute fraction (0..1) of the current track. */
    seekFraction(fraction) {
        if (!this._proxy || this.lengthSec <= 0 || !this.trackId)
            return;

        const targetUsec = Math.round(fraction * this.lengthSec * USEC_PER_SEC);

        this._proxy.call('SetPosition',
            new GLib.Variant('(ox)', [this.trackId, targetUsec]),
            Gio.DBusCallFlags.NONE, -1, this._cancellable,
            (p, res) => {
                try {
                    p.call_finish(res);
                } catch (e) {
                    // Spotify's SetPosition is unreliable; resync shows truth.
                }
                this._syncPosition();
            });

        // Optimistic local update so the bar responds instantly.
        this._basePositionSec = fraction * this.lengthSec;
        this._baseClockUsec = GLib.get_monotonic_time();
    }

    destroy() {
        this._cancellable.cancel();

        if (this._resyncId)
            GLib.source_remove(this._resyncId);
        this._resyncId = 0;

        if (this._proxy && this._propsId)
            this._proxy.disconnect(this._propsId);
        this._proxy = null;
    }
});

/**
 * Watches the session bus for MPRIS players appearing and disappearing, and
 * exposes whichever one we should currently follow.
 */
export const MprisWatcher = GObject.registerClass({
    Signals: {
        'player-changed': {},
        'state-changed': {},
    },
}, class MprisWatcher extends GObject.Object {
    constructor(preferredBusName) {
        super();

        this._preferred = preferredBusName;
        this._players = new Map();
        this._active = null;
        this._cancellable = new Gio.Cancellable();

        this._nameOwnerId = Gio.DBus.session.signal_subscribe(
            'org.freedesktop.DBus', 'org.freedesktop.DBus', 'NameOwnerChanged',
            '/org/freedesktop/DBus', null, Gio.DBusSignalFlags.NONE,
            (conn, sender, path, iface, signal, params) => {
                const [name, oldOwner, newOwner] = params.deepUnpack();
                if (!name.startsWith(MPRIS_PREFIX))
                    return;

                if (newOwner && !oldOwner)
                    this._addPlayer(name);
                else if (!newOwner)
                    this._removePlayer(name);
            });

        this._scanExisting();
    }

    _scanExisting() {
        Gio.DBus.session.call(
            'org.freedesktop.DBus', '/org/freedesktop/DBus',
            'org.freedesktop.DBus', 'ListNames', null,
            new GLib.VariantType('(as)'), Gio.DBusCallFlags.NONE, -1,
            this._cancellable,
            (bus, res) => {
                try {
                    const [names] = bus.call_finish(res).deepUnpack();
                    names.filter(n => n.startsWith(MPRIS_PREFIX))
                        .forEach(n => this._addPlayer(n));
                } catch (e) {
                    logError(e, 'spotify-deck: ListNames failed');
                }
            });
    }

    _addPlayer(busName) {
        if (this._players.has(busName))
            return;

        const player = new MprisPlayer(busName);
        player.connect('changed', () => this._onPlayerChanged(player));
        this._players.set(busName, player);

        this._pickActive();
    }

    _removePlayer(busName) {
        const player = this._players.get(busName);
        if (!player)
            return;

        player.destroy();
        this._players.delete(busName);

        if (this._active === player)
            this._active = null;

        this._pickActive();
    }

    _onPlayerChanged(player) {
        // A player that just started playing takes over the strip.
        if (player.isPlaying && this._active !== player) {
            this._pickActive();
            return;
        }

        if (player === this._active)
            this.emit('state-changed');
    }

    /**
     * Preference order: the configured player if it is playing, then any
     * playing player, then the configured player, then anything at all.
     */
    _pickActive() {
        const all = [...this._players.values()];
        const preferred = all.find(p => p._busName === this._preferred);

        const next =
            (preferred?.isPlaying ? preferred : null) ??
            all.find(p => p.isPlaying) ??
            preferred ??
            all[0] ??
            null;

        if (next === this._active) {
            this.emit('state-changed');
            return;
        }

        this._active = next;
        this.emit('player-changed');
        this.emit('state-changed');
    }

    get active() {
        return this._active;
    }

    setPreferred(busName) {
        this._preferred = busName;
        this._pickActive();
    }

    destroy() {
        this._cancellable.cancel();

        if (this._nameOwnerId)
            Gio.DBus.session.signal_unsubscribe(this._nameOwnerId);
        this._nameOwnerId = 0;

        this._players.forEach(p => p.destroy());
        this._players.clear();
        this._active = null;
    }
});
