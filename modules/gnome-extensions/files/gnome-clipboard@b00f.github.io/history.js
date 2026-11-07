import * as ClipboardItem from './clipboardItem.js';
import * as Settings from './settings.js';
export class History {
    _history;
    constructor() {
        this._history = new Map();
    }
    clear() {
        this._history.clear();
    }
    delete(id) {
        this._history.delete(id);
    }
    get(id) {
        return this._history.get(id);
    }
    set(item) {
        return this._history.set(item.id(), item);
    }
    add(item) {
        if (this._history.has(item.id())) {
            let existing = this._history.get(item.id());
            existing.usage++;
            existing.usedAt = Date.now();
            return true;
        }
        this._history.set(item.id(), item);
        return true;
    }
    trim(total) {
        if (total <= 0) {
            return;
        }
        let arr = this.getSorted(Settings.HISTORY_SORT_COPY_TIME);
        for (let i = total; i < arr.length; ++i) {
            let item = arr[i];
            if (item.pinned) {
                continue;
            }
            this._history.delete(item.id());
        }
    }
    items(only_pinned) {
        let items = [];
        this._history.forEach((item, _) => {
            if (only_pinned) {
                if (item.pinned) {
                    items.push(item);
                }
            }
            else {
                items.push(item);
            }
        });
        return items;
    }
    getItems() {
        return Array.from(this._history.values());
    }
    setItems(items) {
        this._history.clear();
        items.forEach(i => {
            let item = new ClipboardItem.ClipboardItem(i.text, i.usage, i.pinned, i.copiedAt, i.usedAt, i.type, i.imagePath);
            this._history.set(item.id(), item);
        });
    }
    getSorted(sort_by) {
        let arr = Array.from(this._history.values());
        arr.sort((l, r) => {
            if (r.pinned && !l.pinned) {
                return 1;
            }
            if (!r.pinned && l.pinned) {
                return -1;
            }
            switch (sort_by) {
                case Settings.HISTORY_SORT_RECENT_USAGE:
                    return r.usedAt - l.usedAt;
                case Settings.HISTORY_SORT_COPY_TIME:
                    return r.copiedAt - l.copiedAt;
                case Settings.HISTORY_SORT_MOST_USAGE:
                default:
                    if (r.usage == l.usage) {
                        return r.copiedAt - l.copiedAt;
                    }
                    return r.usage - l.usage;
            }
        });
        return arr;
    }
}
