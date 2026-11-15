import St from 'gi://St';
import GObject from 'gi://GObject';
import Clutter from 'gi://Clutter';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as utils from './utils.js';
import * as Tooltip from './tooltip.js';
let _ = (s) => s;
export function init(gettextFunc) {
    _ = gettextFunc;
}
export class MenuItem extends PopupMenu.PopupBaseMenuItem {
    cbInfo;
    _timeLabel;
    _pinBtn;
    static {
        GObject.registerClass(this);
    }
    constructor(cbInfo, onActivate, onPin, onRemove) {
        super({
            style_class: 'clipboard-item',
        });
        this.cbInfo = cbInfo;
        const row = new St.BoxLayout({
            ...utils.boxOrientation(Clutter.Orientation.HORIZONTAL),
            x_expand: true,
            y_align: Clutter.ActorAlign.CENTER,
        });
        const bodyBox = new St.BoxLayout({
            ...utils.boxOrientation(Clutter.Orientation.VERTICAL),
            x_expand: true,
            x_align: Clutter.ActorAlign.START,
            y_align: Clutter.ActorAlign.CENTER,
        });
        bodyBox.add_child(cbInfo.displayWidget());
        this._timeLabel = new St.Label({
            text: this._formatRelativeTime(cbInfo.copiedAt),
            style_class: 'clipboard-item-meta',
            x_align: Clutter.ActorAlign.START,
        });
        bodyBox.add_child(this._timeLabel);
        row.add_child(bodyBox);
        const actionBox = new St.BoxLayout({
            ...utils.boxOrientation(Clutter.Orientation.HORIZONTAL),
            x_align: Clutter.ActorAlign.END,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._pinBtn = this._createActionBtn('view-pin-symbolic', cbInfo.pinned ? 'pinned' : 'unpinned');
        Tooltip.attachTooltip(this._pinBtn, () => (this.cbInfo.pinned ? _('Unpin') : _('Pin')));
        this._pinBtn.connect('clicked', () => onPin(this));
        actionBox.add_child(this._pinBtn);
        const removeBtn = this._createActionBtn('edit-delete-symbolic', 'remove-icon');
        Tooltip.attachTooltip(removeBtn, () => _('Delete'));
        removeBtn.connect('clicked', () => onRemove(this));
        actionBox.add_child(removeBtn);
        row.add_child(actionBox);
        this.add_child(row);
        this.connect('activate', () => {
            onActivate(this);
        });
    }
    updateUI() {
        this._timeLabel.set_text(this._formatRelativeTime(this.cbInfo.copiedAt));
        this._pinBtn.remove_style_class_name('pinned');
        this._pinBtn.remove_style_class_name('unpinned');
        this._pinBtn.add_style_class_name(this.cbInfo.pinned ? 'pinned' : 'unpinned');
    }
    _createActionBtn(iconName, extraClass) {
        return new St.Button({
            style_class: `item-action-btn ${extraClass}`,
            child: new St.Icon({
                icon_name: iconName,
                icon_size: 14,
                style_class: 'popup-menu-icon',
            }),
            can_focus: true,
            track_hover: true,
        });
    }
    // Rice: compact status like the conky cards ("42M AGO", "3H AGO").
    _formatRelativeTime(timestamp) {
        const diff = (Date.now() - timestamp) / 1000;
        if (diff < 60)
            return 'NOW';
        if (diff < 3600)
            return `${Math.floor(diff / 60)}M AGO`;
        if (diff < 86400)
            return `${Math.floor(diff / 3600)}H AGO`;
        return `${Math.floor(diff / 86400)}D AGO`;
    }
    text() {
        return this.cbInfo.searchText();
    }
}
