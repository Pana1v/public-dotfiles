export const SCHEMA_ID = 'org.gnome.shell.extensions.gnome-clipboard';
export const HISTORY_SIZE = "history-size";
export const HISTORY_SORT = "history-sort";
export const CLIPBOARD_TIMER = "clipboard-timer";
export const TIMER_INTERVAL = "timer-interval";
export const SAVE_PINNED = "save-pinned";
export const SHOW_NOTIFICATIONS = "show-notifications";
export const PRIVATE_MODE = "private-mode";
export const BLACKLIST = "blacklist";
export const SHORTCUT_MENU = "shortcut-menu";
export const SHORTCUT_CLEAR = "shortcut-clear";
export const SHORTCUT_PRIVATE_MODE = "shortcut-private-mode";
export const SHORTCUT_NEXT = "shortcut-next";
export const SHORTCUT_PREV = "shortcut-prev";
export const HISTORY_SORT_COPY_TIME = 0;
export const HISTORY_SORT_RECENT_USAGE = 1;
export const HISTORY_SORT_MOST_USAGE = 2;
export class ExtensionSettings {
    _settings;
    constructor(settings) {
        this._settings = settings;
    }
    onChanged(callback) {
        return this._settings.connect('changed', callback);
    }
    historySize() {
        return this._settings.get_uint(HISTORY_SIZE);
    }
    historySort() {
        return this._settings.get_uint(HISTORY_SORT);
    }
    clipboardTimer() {
        return this._settings.get_boolean(CLIPBOARD_TIMER);
    }
    clipboardTimerIntervalInMillisecond() {
        return this._settings.get_uint(TIMER_INTERVAL);
    }
    savePinned() {
        return this._settings.get_boolean(SAVE_PINNED);
    }
    showNotifications() {
        return this._settings.get_boolean(SHOW_NOTIFICATIONS);
    }
    privateMode() {
        return this._settings.get_boolean(PRIVATE_MODE);
    }
    setPrivateMode(value) {
        this._settings.set_boolean(PRIVATE_MODE, value);
    }
    blacklist() {
        return this._settings.get_strv(BLACKLIST);
    }
    shortcutMenu() {
        return this._settings.get_strv(SHORTCUT_MENU);
    }
    shortcutClear() {
        return this._settings.get_strv(SHORTCUT_CLEAR);
    }
    shortcutPrivateMode() {
        return this._settings.get_strv(SHORTCUT_PRIVATE_MODE);
    }
    shortcutNext() {
        return this._settings.get_strv(SHORTCUT_NEXT);
    }
    shortcutPrev() {
        return this._settings.get_strv(SHORTCUT_PREV);
    }
    getSettings() {
        return this._settings;
    }
}
