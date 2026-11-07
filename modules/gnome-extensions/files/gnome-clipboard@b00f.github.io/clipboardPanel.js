import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import GObject from 'gi://GObject';
import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';
import * as History from './history.js';
import * as HistoryMenu from './historyMenu.js';
import * as Settings from './settings.js';
import * as ClipboardItem from './clipboardItem.js';
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
    _menuNeedsRebuild = true;
    constructor(settings, _gettext, uuid, openPrefs) {
        super(0.0, _("Clipboard"), false);
        log.info("initializing ...");
        this._history = new History.History();
        this._settings = new Settings.ExtensionSettings(settings);
        this._openPrefs = openPrefs;
        let path = GLib.get_user_data_dir() + '/' + uuid;
        this._store = new Store.Store(path);
        this._actionBar = new ActionBar.ActionBar();
        this._searchBox = new SearchBox.SearchBox();
        this._historyMenu = new HistoryMenu.HistoryMenu(this._copyToClipboard.bind(this), this._onPinItem.bind(this), this._onRemoveItem.bind(this));
        this.menu.addMenuItem(this._searchBox);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addMenuItem(this._historyMenu);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addMenuItem(this._actionBar);
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
        let icon = new St.Icon({
            icon_name: 'edit-paste-symbolic',
            style_class: 'system-status-icon'
        });
        this.add_child(icon);
        this._actionBar.onClearHistory(this.clearHistory.bind(this));
        this._actionBar.onNextItem(this.selectNextItem.bind(this));
        this._actionBar.onPrevItem(this.selectPrevItem.bind(this));
        this._actionBar.onTogglePrivateMode(this.togglePrivateMode.bind(this));
        this._actionBar.onOpenSettings(() => this._openPrefs());
        this._searchBox.onTextChanged(this._onSearch.bind(this));
        this._openStateChangedID = this.menu.connect('open-state-changed', (_menu, open) => {
            if (open) {
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
    async _loadHistory() {
        let history = await this._store.load();
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
        if (!this._actionBar.enable() || this._settings.privateMode())
            return;
        const clipboard = St.Clipboard.get_default();
        clipboard.get_text(St.ClipboardType.CLIPBOARD, (_cb, text) => {
            try {
                if (text && text.trim().length > 0) {
                    if (this._addClipboard(text)) {
                        this._refresh();
                        this._saveHistoryDebounced();
                    }
                }
                else {
                    this._checkImageClipboard();
                }
            }
            catch (e) {
                log.error(`Check clipboard failed: ${e}`);
            }
        });
    }
    _checkImageClipboard() {
        const clipboard = St.Clipboard.get_default();
        clipboard.get_content(St.ClipboardType.CLIPBOARD, 'image/png', (_cb, bytes) => {
            try {
                if (bytes && bytes.get_size() > 0) {
                    this._processImageBytes(bytes);
                }
            }
            catch (e) { }
        });
    }
    async _processImageBytes(bytes) {
        let id = utils.hashBytes(bytes);
        if (id == this._selectedID)
            return;
        let path = await this._store.saveImage(id, bytes);
        if (path) {
            this._selectedID = id;
            this._addToHistory("", 1, false, Date.now(), Date.now(), ClipboardItem.ClipboardItemType.IMAGE, path);
            this._refresh();
            this._saveHistoryDebounced();
        }
    }
    _addClipboard(text) {
        let id = utils.hashCode(text);
        if (id == this._selectedID)
            return false;
        this._selectedID = id;
        return this._addToHistory(text, 1, false, Date.now(), Date.now(), ClipboardItem.ClipboardItemType.TEXT);
    }
    _addToHistory(text, count, pinned, created, updated, type, path) {
        let item = new ClipboardItem.ClipboardItem(text, count, pinned, created, updated, type, path);
        return this._history.add(item);
    }
    async _copyToClipboard(item) {
        if (item.type === ClipboardItem.ClipboardItemType.IMAGE && item.imagePath) {
            const file = Gio.File.new_for_path(item.imagePath);
            const [bytes] = file.load_bytes(null);
            const source = Meta.SelectionSourceMemory.new('image/png', bytes);
            global.display.get_selection().set_owner(Meta.SelectionType.SELECTION_CLIPBOARD, source);
        }
        else {
            const clipboard = St.Clipboard.get_default();
            clipboard.set_text(St.ClipboardType.CLIPBOARD, item.text);
        }
        this._selectedID = item.id();
        this._refresh();
        if (this._settings.showNotifications()) {
            Main.notify(_("Clipboard updated"), item.display());
        }
    }
    toggleService() {
    }
    clearHistory() {
        const title = _("Clear history?");
        const message = _("Are you sure you want to remove all items?");
        ConfirmDialog.openConfirmDialog(title, message, "", this._doClearHistory.bind(this), _("Empty"));
    }
    togglePrivateMode() {
        this._settings.setPrivateMode(!this._settings.privateMode());
        this._actionBar.setPrivateMode(this._settings.privateMode());
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
        this._history.trim(this._settings.historySize());
        const sorted = this._history.getSorted(this._settings.historySort());
        this._historyMenu.updateNavigation(sorted, this._selectedID);
        this._actionBar.enablePrevButton(this._historyMenu.hasPrevItem());
        this._actionBar.enableNextButton(this._historyMenu.hasNextItem());
        this._menuNeedsRebuild = true;
        if (this.menu.isOpen) {
            this._rebuildMenu(sorted);
        }
    }
    _rebuildMenu(sorted) {
        this._historyMenu.rebuildMenu(sorted ?? this._history.getSorted(this._settings.historySort()), this._selectedID);
        this._onSearch();
        this._menuNeedsRebuild = false;
    }
    _onSearch() {
        let query = this._searchBox.getText().toLowerCase();
        this._historyMenu.filterItems(query);
    }
    _onPinItem(item) {
        item.pinned = !item.pinned;
        this._refresh();
        this._saveHistoryDebounced();
    }
    _onRemoveItem(item) {
        this._history.delete(item.id());
        this._refresh();
        this._saveHistoryDebounced();
    }
    _saveHistoryDebounced() {
        if (this._saveTimerID)
            GLib.source_remove(this._saveTimerID);
        this._saveTimerID = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
            this._store.save(this._history.getItems());
            this._saveTimerID = 0;
            return GLib.SOURCE_REMOVE;
        });
    }
    _doClearHistory() {
        this._history.clear();
        this._store.save([]);
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
        super.destroy();
    }
}
export var ClipboardPanel = GObject.registerClass({
    GTypeName: 'ClipboardPanel'
}, ClipboardPanelInternal);
