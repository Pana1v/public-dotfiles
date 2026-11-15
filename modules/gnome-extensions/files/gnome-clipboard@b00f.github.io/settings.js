export const SCHEMA_ID = 'org.gnome.shell.extensions.gnome-clipboard';
export const HISTORY_SIZE = 'history-size';
export const CLIPBOARD_TIMER = 'clipboard-timer';
export const TIMER_INTERVAL = 'timer-interval';
export const SAVE_PINNED = 'save-pinned';
export const SHOW_NOTIFICATIONS = 'show-notifications';
export const STORE_IMAGES = 'store-images';
export const MAX_IMAGE_SIZE = 'max-image-size';
export const BLACKLIST = 'blacklist';
export const SHORTCUT_MENU = 'shortcut-menu';
export const SHORTCUT_CLEAR = 'shortcut-clear';
export const SHORTCUT_NEXT = 'shortcut-next';
export const SHORTCUT_PREV = 'shortcut-prev';
export const SHORTCUT_CAPTURE = 'shortcut-capture';
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
    storeImages() {
        return this._settings.get_boolean(STORE_IMAGES);
    }
    maxImageSizeInBytes() {
        return this._settings.get_uint(MAX_IMAGE_SIZE) * 1024 * 1024;
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
    shortcutNext() {
        return this._settings.get_strv(SHORTCUT_NEXT);
    }
    shortcutPrev() {
        return this._settings.get_strv(SHORTCUT_PREV);
    }
    shortcutToggleCapture() {
        return this._settings.get_strv(SHORTCUT_CAPTURE);
    }
    getSettings() {
        return this._settings;
    }
}
