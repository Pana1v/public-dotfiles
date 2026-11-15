import Shell from 'gi://Shell';
import Meta from 'gi://Meta';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as ClipboardPanel from './clipboardPanel.js';
import * as ClipboardItemImage from './clipboardItemImage.js';
import * as ActionBar from './actionBar.js';
import * as ConfirmDialog from './confirmDialog.js';
import * as HistoryMenu from './historyMenu.js';
import * as MenuItem from './menuItem.js';
import * as SearchBox from './searchBox.js';
import * as log from './log.js';
import * as Settings from './settings.js';
export default class GnomeClipboardExtension extends Extension {
    _panel = null;
    enable() {
        log.info(`enabling...`);
        log.init(this.getSettings(Settings.SCHEMA_ID));
        if (!this._panel) {
            const gettext = this.gettext.bind(this);
            for (const mod of [
                ClipboardPanel,
                ClipboardItemImage,
                ActionBar,
                ConfirmDialog,
                HistoryMenu,
                MenuItem,
                SearchBox,
            ])
                mod.init(gettext);
            this._panel = new ClipboardPanel.ClipboardPanel(this.getSettings(Settings.SCHEMA_ID), this.gettext.bind(this), this.uuid, () => this.openPreferences());
            Main.panel.addToStatusArea(this.uuid, this._panel);
            if (this._panel)
                this._panel.init();
        }
        this._addKeybinding();
    }
    disable() {
        log.info(`disabling...`);
        this._removeKeybinding();
        if (this._panel) {
            this._panel.destroy();
            this._panel = null;
        }
    }
    _addKeybinding() {
        const settings = this.getSettings(Settings.SCHEMA_ID);
        const wm = Main.wm;
        wm.addKeybinding(Settings.SHORTCUT_MENU, settings, Meta.KeyBindingFlags.NONE, Shell.ActionMode.ALL, () => {
            if (this._panel)
                this._panel.toggle();
        });
        wm.addKeybinding(Settings.SHORTCUT_CLEAR, settings, Meta.KeyBindingFlags.NONE, Shell.ActionMode.ALL, () => {
            if (this._panel)
                this._panel.clearHistory();
        });
        wm.addKeybinding(Settings.SHORTCUT_NEXT, settings, Meta.KeyBindingFlags.NONE, Shell.ActionMode.ALL, () => {
            if (this._panel)
                this._panel.selectNextItem();
        });
        wm.addKeybinding(Settings.SHORTCUT_PREV, settings, Meta.KeyBindingFlags.NONE, Shell.ActionMode.ALL, () => {
            if (this._panel)
                this._panel.selectPrevItem();
        });
        wm.addKeybinding(Settings.SHORTCUT_CAPTURE, settings, Meta.KeyBindingFlags.NONE, Shell.ActionMode.ALL, () => {
            if (this._panel)
                this._panel.toggleCapture();
        });
    }
    _removeKeybinding() {
        const wm = Main.wm;
        wm.removeKeybinding(Settings.SHORTCUT_MENU);
        wm.removeKeybinding(Settings.SHORTCUT_CLEAR);
        wm.removeKeybinding(Settings.SHORTCUT_NEXT);
        wm.removeKeybinding(Settings.SHORTCUT_PREV);
        wm.removeKeybinding(Settings.SHORTCUT_CAPTURE);
    }
}
