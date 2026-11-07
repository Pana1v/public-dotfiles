import St from 'gi://St';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import Clutter from 'gi://Clutter';
import * as ScrollMenu from './scrollMenu.js';
import * as MenuItem from './menuItem.js';
let _ = (s) => s;
export function init(gettextFunc) {
    _ = gettextFunc;
}
export class HistoryMenu extends ScrollMenu.ScrollMenu {
    _onActivateItem;
    _onPinItem;
    _onRemoveItem;
    _nextItem;
    _prevItem;
    _items;
    _headers;
    constructor(onActivateItem, onPinItem, onRemoveItem) {
        super();
        this._onActivateItem = onActivateItem;
        this._onPinItem = onPinItem;
        this._onRemoveItem = onRemoveItem;
        this._nextItem = null;
        this._prevItem = null;
        this._items = new Map();
        this._headers = new Map();
    }
    updateNavigation(history, selectedID) {
        this._nextItem = null;
        this._prevItem = null;
        const index = history.findIndex(h => h.id() === selectedID);
        if (index < 0) {
            return;
        }
        if (index - 1 >= 0) {
            this._nextItem = history[index - 1];
        }
        if (index + 1 < history.length) {
            this._prevItem = history[index + 1];
        }
    }
    rebuildMenu(history, selectedID) {
        if (history.length === 0) {
            super.removeAll();
            this._items.clear();
            this._headers.clear();
            this._showEmptyState();
            return;
        }
        this.scrollViewSection.removeAll();
        this._items.clear();
        this._headers.clear();
        const pinned = history.filter(h => h.pinned);
        const recent = history.filter(h => !h.pinned);
        if (pinned.length > 0) {
            this._addHeader(_("Pinned"));
            pinned.forEach((info) => {
                this._addItem(info, selectedID);
            });
            super.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        }
        if (recent.length > 0) {
            this._addHeader(_("Recent History"));
            recent.forEach((info) => {
                this._addItem(info, selectedID);
            });
        }
    }
    _addHeader(title) {
        let header = new PopupMenu.PopupBaseMenuItem({
            reactive: false,
            activate: false,
            style_class: 'section-header'
        });
        header.add_child(new St.Label({ text: title, style_class: 'section-header-label' }));
        super.addMenuItem(header);
    }
    _addItem(info, selectedID) {
        let item = new MenuItem.MenuItem(info, this.onActivateItem.bind(this), this.onPinItem.bind(this), this.onRemoveItem.bind(this));
        this._items.set(info.id(), item);
        if (info.id() == selectedID) {
            item.add_style_class_name('selected');
        }
        else {
            item.remove_style_class_name('selected');
        }
        super.addMenuItem(item);
    }
    _showEmptyState() {
        let box = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            x_expand: true,
            y_expand: true,
            style_class: 'empty-state',
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER
        });
        let icon = new St.Icon({
            icon_name: 'edit-copy-symbolic',
            style_class: 'empty-state-icon'
        });
        box.add_child(icon);
        let label = new St.Label({
            text: _("Clipboard is empty"),
            style_class: 'empty-state-label'
        });
        box.add_child(label);
        let container = new PopupMenu.PopupBaseMenuItem({
            reactive: false,
            activate: false,
            hover: false
        });
        container.add_child(box);
        super.addMenuItem(container);
    }
    nextItem() {
        return this._nextItem;
    }
    prevItem() {
        return this._prevItem;
    }
    hasNextItem() {
        return this._nextItem != null;
    }
    hasPrevItem() {
        return this._prevItem != null;
    }
    scrollToItem(id) {
        const item = this._items.get(id);
        if (item) {
            for (const [itemId, menuItem] of this._items) {
                if (itemId === id) {
                    menuItem.add_style_class_name('selected');
                }
                else {
                    menuItem.remove_style_class_name('selected');
                }
            }
            const adjustment = this.scrollView.get_vscroll_bar().get_adjustment();
            const value = adjustment.value;
            const pageSize = adjustment.page_size;
            const alloc = item.get_allocation_box();
            const itemY = alloc.y1;
            const itemHeight = item.height;
            if (itemY < value) {
                adjustment.set_value(itemY);
            }
            else if (itemY + itemHeight > value + pageSize) {
                adjustment.set_value(itemY + itemHeight - pageSize);
            }
        }
    }
    updateItemsUI() {
        for (const item of this._items.values()) {
            item.updateUI();
        }
    }
    filterItems(query) {
        for (const [_id, item] of this._items) {
            if (!query || query.length === 0) {
                item.actor?.show?.();
                item.show?.();
            }
            else {
                const text = item.cbInfo.text?.toLowerCase() ?? '';
                const matches = text.includes(query);
                if (matches) {
                    item.actor?.show?.();
                    item.show?.();
                }
                else {
                    item.actor?.hide?.();
                    item.hide?.();
                }
            }
        }
    }
    onActivateItem(item) {
        this._onActivateItem(item.cbInfo);
    }
    onRemoveItem(item) {
        this._onRemoveItem(item.cbInfo);
    }
    onPinItem(item) {
        this._onPinItem(item.cbInfo);
    }
}
;
