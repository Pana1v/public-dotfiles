# Spotify Deck

An always-visible player strip for the taskbar: album art, scrolling track
text, a live spectrum, a progress hairline, and transport controls that appear
on hover.

```
[art] Track Name          ▁▃▅▇▆▄▂▅  ⏮ ⏸ ⏭
      Artist
──────────────────────────                  <- progress, tinted by the cover
```

## How it fits together

```
  Spotify (Flatpak)
        │ MPRIS over D-Bus
        ▼
  src/mpris.js ──────────► src/art.js ────► ~/.cache/spotify-deck/
   track, status,           cover fetch      (content-addressed by URL)
   interpolated position         │
        │                        │ accent colour
        ▼                        ▼
  extension.js ──────────► src/strip.js  (St + Cairo drawing)
        ▲
        │ normalised bars 0..1
  src/viz.js
        │
        ├─ cava (separate process, does the FFT) ── if installed
        └─ synthesised waveform ───────────────── otherwise
```

## Design decisions worth knowing

**The FFT runs in another process.** A GNOME extension executes inside the
compositor, on its main loop, with no worker threads. Doing a 60fps transform
there would stutter the entire desktop. `cava` is a small C program that does
the transform and writes raw 16-bit bands to a pipe; this extension only reads
bytes and draws.

**There is always a fallback**, for three separate failure modes:

| Situation | Behaviour |
|---|---|
| cava not installed | synthesised waveform |
| cava crashes or its stream dies | synthesised waveform |
| cava fine, but the device is silent while MPRIS says Playing | synthesised waveform after 4s, cava reclaims the bars the instant real audio returns |

The third case is the subtle one. A player can report `Playing` while producing
no audio at all: its output device may have gone away (disconnected bluetooth
is the usual cause) or it may be routed somewhere the monitor source cannot
see. cava then reports perfectly honest silence, the bars go flat, and the
widget reads as broken rather than as quiet. The grace period has to be
generous or quiet passages in real music would trip it.

Install cava for real spectrum:

```
sudo apt install cava
```

If the bars animate but never react to the music, the audio is not reaching the
sink cava monitors. Check which device is actually active:

```
pw-metadata -n default | grep 'default.audio.sink'
```

**Position is interpolated, not polled.** Spotify never emits
`PropertiesChanged` for `Position`, so a progress bar driven purely off D-Bus
appears frozen. The strip advances position locally from a monotonic clock and
re-syncs against the real value every 10 seconds.

**Album art cannot be loaded directly.** `mpris:artUrl` is an `https://`
address and St widgets only load local files, so every cover is fetched with
Soup, cached to disk, and shown via CSS `background-image`.

**The accent colour is weighted, not averaged.** A plain pixel mean of album
art returns mud, because opposing hues cancel out. Each pixel is weighted by
saturation squared times value, which biases toward the vivid pixels a person
would actually name as the cover's colour.

**The spectrum is gated on playback.** cava monitors the whole audio device,
not just Spotify, so the bars would otherwise react to notifications and
browser audio while the strip claims to be paused.

## Files

| File | Responsibility |
|---|---|
| `extension.js` | Wiring and lifecycle |
| `src/mpris.js` | D-Bus player binding, position model |
| `src/viz.js` | Spectrum source: cava, or synthesised |
| `src/art.js` | Cover download, disk cache, accent colour |
| `src/strip.js` | All drawing and layout |

## Tuning

Sizes live at the top of `src/strip.js` (`ART_SIZE`, `BAR_COUNT`, `VIZ_WIDTH`)
and widths in `stylesheet.css`.
