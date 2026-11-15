import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import GLib from 'gi://GLib';
import St from 'gi://St';
import GObject from 'gi://GObject';
import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as History from './history.js';
import * as HistoryMenu from './historyMenu.js';
import * as Settings from './settings.js';
import { ClipboardItemImage } from './clipboardItemImage.js';
import { ClipboardItemText } from './clipboardItemText.js';
import * as Store from './store.js';
import * as log from './log.js';
import * as utils from './utils.js';
import * as ConfirmDialog from './confirmDialog.js';
import * as ActionBar from './actionBar.js';
import * as SearchBox from './searchBox.js';
let _ = (s) => s;
export function init(gettextFunc) {
    _ = gettextFunc;
}
class ClipboardPanelInternal extends PanelMenu.Button {
    _history;
    _historyMenu;
    _settings;
    _actionBar;
    _searchBox;
    _store;
    _openPrefs;
    _clipboardTimerID = 0;
    _saveTimerID = 0;
    _selectedID = 0;
    _openStateChangedID = 0;
    _keyPressEventID = 0;
    _focusTimerID = 0;
    _selectionOwnerChangedID = 0;
    _settingsChangedID = 0;
    _menuNeedsRebuild = true;
    constructor(settings, _gettext, uuid, openPrefs) {
        super(0.0, _('Clipboard'), false);
        log.info('initializing ...');
        this._history = new History.History();
        this._settings = new Settings.ExtensionSettings(settings);
        this._openPrefs = openPrefs;
        const path = GLib.get_user_data_dir() + '/' + uuid;
        this._store = new Store.Store(path);
        this._actionBar = new ActionBar.ActionBar();
        this._searchBox = new SearchBox.SearchBox();
        this._historyMenu = new HistoryMenu.HistoryMenu(this._copyToClipboard.bind(this), this._onPinItem.bind(this), this._onRemoveItem.bind(this));
        this.menu.addMenuItem(this._searchBox);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addMenuItem(this._historyMenu);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addMenuItem(this._actionBar);
        this._settingsChangedID = this._settings.onChanged(() => {
            this._refresh();
        });
        this._setupUI();
        this._loadHistory();
        this._setupClipboardMonitoring();
    }
    init() {
    }
    toggle() {
        this.menu.toggle();
    }
    _setupUI() {
        this.menu.box.add_style_class_name('gnome-clipboard');
        const icon = new St.Icon({
            icon_name: 'edit-paste-symbolic',
            style_class: 'system-status-icon',
        });
        this.add_child(icon);
        this._actionBar.onClearHistory(this.clearHistory.bind(this));
        this._actionBar.onNextItem(this.selectNextItem.bind(this));
        this._actionBar.onPrevItem(this.selectPrevItem.bind(this));
        this._actionBar.onOpenSettings(() => this._openPrefs());
        this._searchBox.onTextChanged(this._onSearch.bind(this));
        this._openStateChangedID = this.menu.connect('open-state-changed', (_menu, open) => {
            if (open) {
                this._updateThemeVariant();
                if (this._menuNeedsRebuild) {
                    this._rebuildMenu();
                }
                if (this._focusTimerID)
                    GLib.source_remove(this._focusTimerID);
                this._focusTimerID = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
                    this._searchBox.setText('');
                    global.stage.set_key_focus(this._searchBox.searchEntry);
                    this._focusTimerID = 0;
                    return GLib.SOURCE_REMOVE;
                });
            }
        });
        this._keyPressEventID = this._historyMenu.scrollView.connect('key-press-event', (_widget, _event) => {
            global.stage.set_key_focus(this._searchBox.searchEntry);
            return Clutter.EVENT_PROPAGATE;
        });
    }
    _updateThemeVariant() {
        const bg = this.menu.box.get_theme_node().get_background_color();
        const luminance = (0.2126 * bg.red + 0.7152 * bg.green + 0.0722 * bg.blue) / 255;
        if (luminance > 0.5)
            this.menu.box.add_style_class_name('light');
        else
            this.menu.box.remove_style_class_name('light');
    }
    async _loadHistory() {
        const history = await this._store.load();
        if (history && history.length > 0) {
            this._history.setItems(history);
            this._refresh();
        }
        this._checkClipboard();
    }
    _setupClipboardMonitoring() {
        if (this._settings.clipboardTimer()) {
            const interval = this._settings.clipboardTimerIntervalInMillisecond();
            log.info(`polling clipboard every ${interval} ms`);
            this._clipboardTimerID = GLib.timeout_add(GLib.PRIORITY_DEFAULT, interval, () => {
                this._checkClipboard();
                return GLib.SOURCE_CONTINUE;
            });
            return;
        }
        const selection = global.display.get_selection();
        this._selectionOwnerChangedID = selection.connect('owner-changed', (_selection, selectionType) => {
            if (selectionType === Meta.SelectionType.SELECTION_CLIPBOARD) {
                this._checkClipboard();
            }
        });
    }
    _checkClipboard() {
        if (!this._actionBar.enable())
            return;
        if (this._isFocusAppBlacklisted())
            return;
        const clipboard = St.Clipboard.get_default();
        let mimetypes = [];
        try {
            mimetypes = clipboard.get_mimetypes(St.ClipboardType.CLIPBOARD) ?? [];
        }
        catch (e) {
            log.warn(`unable to read clipboard mimetypes: ${e}`);
        }
        log.debug(`clipboard mimetypes: ${mimetypes.join(', ')}`);
        const hasText = mimetypes.some((m) => m.startsWith('text/'));
        const hasImage = mimetypes.some((m) => m.startsWith('image/'));
        const onSave = (item) => {
            this._history.add(item);
            this._selectedID = item.id;
            this._refresh();
            this._saveHistoryDebounced();
        };
        if (hasImage) {
            this._checkImageClipboard(clipboard, onSave);
        }
        if (hasText) {
            this._checkTextClipboard(clipboard, onSave);
        }
    }
    _checkTextClipboard(clipboard, onSave) {
        clipboard.get_text(St.ClipboardType.CLIPBOARD, (_cb, text) => {
            if (!text || text.trim().length === 0)
                return;
            const id = utils.hashText(text);
            onSave(new ClipboardItemText(id, text));
        });
    }
    _checkImageClipboard(clipboard, onSave) {
        if (!this._settings.storeImages())
            return;
        clipboard.get_content(St.ClipboardType.CLIPBOARD, 'image/png', async (_cb, bytes) => {
            if (!bytes || bytes.get_size() === 0)
                return;
            const maxBytes = this._settings.maxImageSizeInBytes();
            if (maxBytes > 0 && bytes.get_size() > maxBytes) {
                log.info(`ignoring image of ${bytes.get_size()} bytes, larger than ${maxBytes} bytes`);
                return;
            }
            const id = utils.hashByte(bytes);
            onSave(new ClipboardItemImage(id));
            const saved = await this._store.saveImage(id, bytes);
            if (!saved) {
                log.error(`failed to save image ${id}`);
            }
        });
    }
    async _copyToClipboard(item) {
        await item.copyToClipboard();
        this._selectedID = item.id;
        this._refresh();
        if (this._settings.showNotifications()) {
            Main.notify(_('Clipboard updated'), item.notification());
        }
    }
    toggleService() {
    }
    toggleCapture() {
        const enabled = this._actionBar.toggleCapture();
        if (this._settings.showNotifications()) {
            Main.notify(_('Gnome Clipboard'), enabled ? _('Clipboard capture enabled') : _('Clipboard capture paused'));
        }
    }
    clearHistory() {
        const title = _('Clear history?');
        const message = _('Are you sure you want to remove all items?');
        ConfirmDialog.openConfirmDialog(title, message, '', this._doClearHistory.bind(this), _('Empty'));
    }
    selectNextItem() {
        const next = this._historyMenu.nextItem();
        if (next)
            this._copyToClipboard(next);
    }
    selectPrevItem() {
        const prev = this._historyMenu.prevItem();
        if (prev)
            this._copyToClipboard(prev);
    }
    _refresh() {
        this._disposeItems(this._history.trim(this._settings.historySize()));
        const sorted = this._history.getSorted();
        this._historyMenu.updateNavigation(sorted, this._selectedID);
        this._actionBar.enablePrevButton(this._historyMenu.hasPrevItem());
        this._actionBar.enableNextButton(this._historyMenu.hasNextItem());
        this._menuNeedsRebuild = true;
        if (this.menu.isOpen) {
            this._rebuildMenu(sorted);
        }
    }
    _rebuildMenu(sorted) {
        this._historyMenu.rebuildMenu(sorted ?? this._history.getSorted(), this._selectedID);
        this._onSearch();
        this._menuNeedsRebuild = false;
    }
    _onSearch() {
        const query = this._searchBox.getText().toLowerCase();
        this._historyMenu.filterItems(query);
    }
    _onPinItem(item) {
        item.pinned = !item.pinned;
        this._refresh();
        this._saveHistoryDebounced();
    }
    _onRemoveItem(item) {
        this._history.delete(item.id);
        this._disposeItems([item]);
        this._refresh();
        this._saveHistoryDebounced();
    }
    _saveHistoryDebounced() {
        if (this._saveTimerID)
            GLib.source_remove(this._saveTimerID);
        this._saveTimerID = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
            this._store.save(this._history.items(this._settings.savePinned()));
            this._saveTimerID = 0;
            return GLib.SOURCE_REMOVE;
        });
    }
    _disposeItems(items) {
        for (const item of items) {
            item.dispose(this._store);
        }
    }
    _isFocusAppBlacklisted() {
        const blacklist = this._settings.blacklist();
        if (blacklist.length === 0)
            return false;
        const app = Shell.WindowTracker.get_default().focus_app;
        const win = global.display.focus_window;
        const id = app?.get_id() ?? '';
        const candidates = [
            id,
            id.replace(/\.desktop$/, ''),
            app?.get_name() ?? '',
            win?.get_wm_class() ?? '',
            win?.get_gtk_application_id() ?? '',
            win?.get_sandboxed_app_id() ?? '',
        ]
            .filter((s) => s.length > 0)
            .map((s) => s.toLowerCase());
        const blocked = blacklist.some((entry) => candidates.includes(entry.toLowerCase()));
        if (blocked)
            log.info(`skipping blacklisted app: ${candidates.join(', ')}`);
        return blocked;
    }
    _doClearHistory() {
        this._disposeItems(this._history.getItems());
        this._history.clear();
        this._store.clearAll();
        this._refresh();
    }
    destroy() {
        if (this._clipboardTimerID)
            GLib.source_remove(this._clipboardTimerID);
        if (this._saveTimerID)
            GLib.source_remove(this._saveTimerID);
        if (this._focusTimerID)
            GLib.source_remove(this._focusTimerID);
        if (this._openStateChangedID) {
            this.menu.disconnect(this._openStateChangedID);
            this._openStateChangedID = 0;
        }
        if (this._keyPressEventID) {
            this._historyMenu.scrollView.disconnect(this._keyPressEventID);
            this._keyPressEventID = 0;
        }
        if (this._selectionOwnerChangedID) {
            global.display.get_selection().disconnect(this._selectionOwnerChangedID);
            this._selectionOwnerChangedID = 0;
        }
        if (this._settingsChangedID) {
            this._settings.getSettings().disconnect(this._settingsChangedID);
            this._settingsChangedID = 0;
        }
        super.destroy();
    }
}
export const ClipboardPanel = GObject.registerClass({
    GTypeName: 'ClipboardPanel',
}, ClipboardPanelInternal);
