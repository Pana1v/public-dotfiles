import * as ClipboardItem from './clipboardItem.js';
import './clipboardItemText.js';
import './clipboardItemImage.js';
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
    contains(id) {
        return this._history.has(id);
    }
    get(id) {
        return this._history.get(id);
    }
    add(item) {
        if (this._history.has(item.id)) {
            const existing = this._history.get(item.id);
            existing.updateLastUsed();
            return false;
        }
        this._history.set(item.id, item);
        return true;
    }
    trim(total) {
        const removed = [];
        if (total <= 0) {
            return removed;
        }
        const arr = this.getSorted('usedAt');
        for (let i = total; i < arr.length; ++i) {
            const item = arr[i];
            if (item.pinned) {
                continue;
            }
            this._history.delete(item.id);
            removed.push(item);
        }
        return removed;
    }
    items(only_pinned) {
        const items = [];
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
        items.forEach((i) => {
            const item = ClipboardItem.ClipboardItem.fromJSON(i);
            this._history.set(item.id, item);
        });
    }
    getSorted(by = 'copiedAt') {
        const arr = Array.from(this._history.values());
        arr.sort((l, r) => {
            if (r.pinned && !l.pinned) {
                return 1;
            }
            if (!r.pinned && l.pinned) {
                return -1;
            }
            return r[by] - l[by];
        });
        return arr;
    }
}
