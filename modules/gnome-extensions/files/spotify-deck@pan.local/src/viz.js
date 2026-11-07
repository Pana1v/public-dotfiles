import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';

// cava emits one frame per tick: BAR_COUNT unsigned 16-bit LE samples.
const BYTES_PER_SAMPLE = 2;
const SAMPLE_MAX = 65535;

const CAVA_FRAMERATE = 60;
const SYNTH_FRAMERATE = 30;

// Bars decay toward a new lower value instead of snapping, which reads as
// momentum rather than flicker. Higher = slower fall.
const FALL_SMOOTHING = 0.72;
const RISE_SMOOTHING = 0.30;

// A player can report Playing while producing no audio at all: its output
// device may have gone away (disconnected bluetooth is the common case), or it
// may be routed somewhere the monitor source does not see. cava then reports
// honest silence and the widget goes flat, which reads as broken rather than
// as quiet. Past this grace period the synthesised waveform takes over, and
// real audio reclaims the bars the moment it returns.
const SILENCE_LEVEL = 0.01;
const SILENCE_GRACE_SEC = 4;

export const VizMode = {
    CAVA: 'cava',
    SYNTH: 'synth',
};

/**
 * Produces a normalised bar array (values 0..1) for the strip to draw.
 *
 * Real spectrum comes from cava, a small C helper that owns the FFT. The
 * extension runs inside the compositor process with no worker threads, so
 * doing the transform here would stutter the whole desktop; we only ever
 * read bytes and draw.
 *
 * When cava is absent the engine falls back to a synthesised waveform so the
 * widget animates instead of sitting visibly dead.
 */
export const VizEngine = GObject.registerClass({
    Signals: {
        'bars': {param_types: [GObject.TYPE_JSOBJECT]},
        'mode-changed': {},
    },
}, class VizEngine extends GObject.Object {
    constructor(barCount) {
        super();

        this._barCount = barCount;
        this._bars = new Array(barCount).fill(0);
        this._active = false;
        this._mode = null;

        this._proc = null;
        this._stdout = null;
        this._cancellable = null;
        this._configPath = null;
        this._buffer = new Uint8Array(0);
        this._bufferUsed = 0;

        this._synthId = 0;
        this._synthPhase = 0;

        this._silentSince = 0;
        this._coveringSilence = false;
    }

    get mode() {
        return this._mode;
    }

    get barCount() {
        return this._barCount;
    }

    get hasRealAudio() {
        return this._mode === VizMode.CAVA;
    }

    /** Start or stop producing frames. Idle costs nothing. */
    setActive(active) {
        if (this._active === active)
            return;

        this._active = active;

        if (active)
            this._start();
        else
            this._stop();
    }

    _start() {
        if (GLib.find_program_in_path('cava') && this._startCava())
            return;

        this._startSynth();
    }

    _stop() {
        this._stopCava();
        this._stopSynth();

        this._silentSince = 0;
        this._coveringSilence = false;

        this._bars.fill(0);
        this._mode = null;
        this.emit('bars', this._bars);
    }

    _setMode(mode) {
        if (this._mode === mode)
            return;
        this._mode = mode;
        this.emit('mode-changed');
    }

    // --- real spectrum -----------------------------------------------------

    _cavaConfig() {
        return [
            '[general]',
            `bars = ${this._barCount}`,
            `framerate = ${CAVA_FRAMERATE}`,
            'autosens = 1',
            'lower_cutoff_freq = 50',
            'higher_cutoff_freq = 10000',
            '[smoothing]',
            'monstercat = 1.5',
            'waves = 0',
            'noise_reduction = 55',
            '[input]',
            'method = pulse',
            'source = auto',
            '[output]',
            'method = raw',
            'bit_format = 16bit',
            'channels = mono',
            'raw_target = /dev/stdout',
            '',
        ].join('\n');
    }

    _startCava() {
        try {
            this._configPath = GLib.build_filenamev([
                GLib.get_tmp_dir(),
                `spotify-deck-cava-${GLib.get_monotonic_time()}.conf`,
            ]);
            GLib.file_set_contents(this._configPath,
                new TextEncoder().encode(this._cavaConfig()));

            const launcher = new Gio.SubprocessLauncher({
                flags: Gio.SubprocessFlags.STDOUT_PIPE |
                       Gio.SubprocessFlags.STDERR_SILENCE,
            });

            this._proc = launcher.spawnv(['cava', '-p', this._configPath]);
            this._stdout = this._proc.get_stdout_pipe();
            this._cancellable = new Gio.Cancellable();

            this._buffer = new Uint8Array(this._frameSize() * 8);
            this._bufferUsed = 0;

            this._setMode(VizMode.CAVA);
            this._readFrames();

            return true;
        } catch (e) {
            logError(e, 'spotify-deck: cava launch failed');
            this._stopCava();
            return false;
        }
    }

    _frameSize() {
        return this._barCount * BYTES_PER_SAMPLE;
    }

    _readFrames() {
        if (!this._stdout || this._cancellable?.is_cancelled())
            return;

        this._stdout.read_bytes_async(
            this._frameSize() * 4, GLib.PRIORITY_DEFAULT, this._cancellable,
            (stream, res) => {
                let chunk;
                try {
                    chunk = stream.read_bytes_finish(res)?.get_data();
                } catch (e) {
                    if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        this._fallbackFromCava(e);
                    return;
                }

                // Empty read means cava exited; degrade rather than go dead.
                if (!chunk || chunk.length === 0) {
                    this._fallbackFromCava(null);
                    return;
                }

                this._consume(chunk);
                this._readFrames();
            });
    }

    _consume(chunk) {
        const frameSize = this._frameSize();
        const needed = this._bufferUsed + chunk.length;

        if (needed > this._buffer.length) {
            const grown = new Uint8Array(Math.max(needed, this._buffer.length * 2));
            grown.set(this._buffer.subarray(0, this._bufferUsed));
            this._buffer = grown;
        }

        this._buffer.set(chunk, this._bufferUsed);
        this._bufferUsed = needed;

        const frames = Math.floor(this._bufferUsed / frameSize);
        if (frames === 0)
            return;

        // Only the newest complete frame matters; older ones are already stale
        // by the time we draw, and keeping them would build visible lag.
        const lastStart = (frames - 1) * frameSize;
        const view = new DataView(this._buffer.buffer, lastStart, frameSize);

        const next = new Array(this._barCount);
        for (let i = 0; i < this._barCount; i++)
            next[i] = view.getUint16(i * BYTES_PER_SAMPLE, true) / SAMPLE_MAX;

        this._trackSilence(Math.max(...next));

        // While covering silence the synth timer owns the output; dropping
        // these frames keeps the two sources from fighting over the bars.
        if (!this._coveringSilence)
            this._emitSmoothed(next);

        // Retain the partial frame tail.
        const consumed = frames * frameSize;
        this._buffer.copyWithin(0, consumed, this._bufferUsed);
        this._bufferUsed -= consumed;
    }

    /**
     * Decides whether cava is reporting real audio or a silent device.
     * Only silence long enough to rule out a quiet passage flips the source.
     */
    _trackSilence(peak) {
        const now = GLib.get_monotonic_time() / 1000000;

        if (peak > SILENCE_LEVEL) {
            this._silentSince = 0;

            if (this._coveringSilence) {
                this._coveringSilence = false;
                this._stopSynth();
            }
            return;
        }

        if (this._silentSince === 0) {
            this._silentSince = now;
            return;
        }

        if (!this._coveringSilence && now - this._silentSince >= SILENCE_GRACE_SEC) {
            this._coveringSilence = true;
            this._startSynth();
        }
    }

    _fallbackFromCava(error) {
        if (error)
            logError(error, 'spotify-deck: cava stream failed');

        this._stopCava();

        if (this._active)
            this._startSynth();
    }

    _stopCava() {
        this._cancellable?.cancel();
        this._cancellable = null;

        try {
            this._proc?.force_exit();
        } catch (e) {
            // Already gone.
        }
        this._proc = null;
        this._stdout = null;

        if (this._configPath) {
            GLib.unlink(this._configPath);
            this._configPath = null;
        }

        this._bufferUsed = 0;
    }

    // --- synthesised fallback ---------------------------------------------

    _startSynth() {
        if (this._synthId)
            return;

        // Covering a silent device is not a mode change: cava is still the
        // source of truth and reclaims the bars as soon as audio returns.
        if (!this._coveringSilence)
            this._setMode(VizMode.SYNTH);

        this._synthId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT, Math.round(1000 / SYNTH_FRAMERATE), () => {
                this._synthTick();
                return GLib.SOURCE_CONTINUE;
            });
    }

    /**
     * Shapes noise into something spectrum-like: a bass-weighted envelope so
     * low bars dominate, several detuned oscillators so neighbouring bars move
     * together rather than independently, and a slow pulse for overall energy.
     */
    _synthTick() {
        this._synthPhase += 0.12;

        const energy = 0.55 + 0.25 * Math.sin(this._synthPhase * 0.35);
        const next = new Array(this._barCount);

        for (let i = 0; i < this._barCount; i++) {
            const t = i / Math.max(this._barCount - 1, 1);

            // Low frequencies carry more amplitude in real music.
            const tilt = Math.pow(1 - t, 1.4) * 0.75 + 0.25;

            const wave =
                0.5 * Math.sin(this._synthPhase * 1.7 + i * 0.45) +
                0.3 * Math.sin(this._synthPhase * 2.9 + i * 0.21) +
                0.2 * Math.sin(this._synthPhase * 4.3 + i * 0.83);

            const jitter = (Math.random() - 0.5) * 0.18;
            const v = energy * tilt * (0.55 + 0.45 * wave) + jitter;

            next[i] = Math.max(0, Math.min(1, v));
        }

        this._emitSmoothed(next);
    }

    _stopSynth() {
        if (this._synthId)
            GLib.source_remove(this._synthId);
        this._synthId = 0;
    }

    // --- shared ------------------------------------------------------------

    /** Asymmetric smoothing: quick attack, slow release. */
    _emitSmoothed(next) {
        for (let i = 0; i < this._barCount; i++) {
            const target = next[i];
            const prev = this._bars[i];
            const k = target > prev ? RISE_SMOOTHING : FALL_SMOOTHING;

            this._bars[i] = prev * k + target * (1 - k);
        }

        this.emit('bars', this._bars);
    }

    destroy() {
        this._active = false;
        this._stop();
    }
});
