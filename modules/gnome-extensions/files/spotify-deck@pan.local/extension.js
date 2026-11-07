import GObject from 'gi://GObject';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

import {MprisWatcher} from './src/mpris.js';
import {VizEngine} from './src/viz.js';
import {ArtCache} from './src/art.js';
import {DeckStrip} from './src/strip.js';

const SPOTIFY_BUS = 'org.mpris.MediaPlayer2.spotify';
const PANEL_ROLE = 'spotify-deck';

// Left end of the panel, right after the menu button.
const PANEL_BOX = 'left';
const MENU_ROLE = 'zorin-menu';

const DeckIndicator = GObject.registerClass(
class DeckIndicator extends PanelMenu.Button {
    constructor() {
        // The third argument suppresses menu creation: the strip is always
        // visible and self-contained, so a popup would only get in the way.
        super(0.0, 'Spotify Deck', true);

        this.add_style_class_name('spotify-deck-indicator');

        this._strip = new DeckStrip();
        this.add_child(this._strip);
    }

    get strip() {
        return this._strip;
    }
});

export default class SpotifyDeckExtension extends Extension {
    enable() {
        this._indicator = new DeckIndicator();
        this._strip = this._indicator.strip;

        this._art = new ArtCache();
        this._viz = new VizEngine(DeckStrip.BAR_COUNT);
        this._watcher = new MprisWatcher(SPOTIFY_BUS);

        this._wireStrip();
        this._wireViz();
        this._wireArt();
        this._wireWatcher();

        Main.panel.addToStatusArea(
            PANEL_ROLE, this._indicator, this._panelIndex(), PANEL_BOX);

        this._sync();
    }

    /**
     * Extensions enable in no fixed order. If the menu is already in the box,
     * go right after it; if not, index 0 still ends up after it, because the
     * menu inserts itself at 0 when it arrives.
     */
    _panelIndex() {
        const menu = Main.panel.statusArea[MENU_ROLE];
        if (!menu)
            return 0;

        return Main.panel._leftBox.get_children().indexOf(menu.container) + 1;
    }

    _wireStrip() {
        this._strip.connect('control', (_s, action) => {
            const player = this._watcher.active;
            if (!player)
                return;

            if (action === 'playpause')
                player.playPause();
            else if (action === 'next')
                player.next();
            else if (action === 'previous')
                player.previous();
        });

        this._strip.trackProgress(() => {
            const player = this._watcher.active;
            return {
                position: player?.positionSec ?? 0,
                length: player?.lengthSec ?? 0,
            };
        });
    }

    _wireViz() {
        this._vizId = this._viz.connect('bars',
            (_e, bars) => this._strip.setBars(bars));
    }

    _wireArt() {
        this._artId = this._art.connect('ready', (_c, url, result) => {
            // A slow download may land after the track already changed.
            if (url !== this._watcher.active?.artUrl)
                return;

            this._strip.setArtPath(result.path);
            this._strip.setAccent(result.accent);
        });
    }

    _wireWatcher() {
        this._watcher.connect('state-changed', () => this._sync());
        this._watcher.connect('player-changed', () => this._sync());
    }

    _sync() {
        const player = this._watcher.active;

        // With no player on the bus at all there is nothing to show, and an
        // empty strip would just be dead panel space.
        this._indicator.visible = !!player;

        if (!player) {
            this._viz.setActive(false);
            return;
        }

        this._strip.setTrack({title: player.title, artist: player.artist});
        this._strip.setPlaying(player.isPlaying);
        this._strip.setCanSkip({
            next: player.canGoNext,
            previous: player.canGoPrevious,
        });

        if (player.artUrl) {
            const cached = this._art.pathFor(player.artUrl);
            if (cached) {
                this._strip.setArtPath(cached);
                this._strip.setAccent(this._art.accentFor(player.artUrl));
            }
            this._art.request(player.artUrl);
        } else {
            this._strip.setArtPath(null);
            this._strip.setAccent(null);
        }

        // The spectrum monitors the whole audio device, so gate it on actual
        // playback; otherwise notification blips would drive the bars while
        // the strip claims to be paused.
        this._viz.setActive(player.isPlaying);
    }

    disable() {
        if (this._vizId)
            this._viz.disconnect(this._vizId);
        if (this._artId)
            this._art.disconnect(this._artId);

        this._watcher?.destroy();
        this._viz?.destroy();
        this._art?.destroy();
        this._indicator?.destroy();

        this._watcher = null;
        this._viz = null;
        this._art = null;
        this._indicator = null;
        this._strip = null;
        this._vizId = 0;
        this._artId = 0;
    }
}
