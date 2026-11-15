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
export class ActionBar extends PopupMenu.PopupBaseMenuItem {
    _clearBtn;
    _settingsBtn;
    _prevBtn;
    _nextBtn;
    _enableBtn;
    static {
        GObject.registerClass(this);
    }
    constructor() {
        super({
            reactive: false,
            activate: false,
            hover: false,
            can_focus: false,
            style_class: 'action-bar-container',
        });
        const mainBox = new St.BoxLayout({
            ...utils.boxOrientation(Clutter.Orientation.HORIZONTAL),
            x_expand: true,
            style_class: 'action-bar',
        });
        const navBox = new St.BoxLayout({
            ...utils.boxOrientation(Clutter.Orientation.HORIZONTAL),
            style_class: 'nav-group',
        });
        this._prevBtn = this._createIconButton('go-previous-symbolic');
        Tooltip.attachTooltip(this._prevBtn, () => _('Previous Item'));
        this._nextBtn = this._createIconButton('go-next-symbolic');
        Tooltip.attachTooltip(this._nextBtn, () => _('Next Item'));
        navBox.add_child(this._prevBtn);
        navBox.add_child(this._nextBtn);
        mainBox.add_child(navBox);
        const spacer = new St.Widget({ x_expand: true });
        mainBox.add_child(spacer);
        const actionBox = new St.BoxLayout({
            ...utils.boxOrientation(Clutter.Orientation.HORIZONTAL),
            style_class: 'action-group',
        });
        this._clearBtn = this._createIconButton('edit-delete-symbolic', 'action-btn-danger');
        Tooltip.attachTooltip(this._clearBtn, () => _('Clear History'));
        this._settingsBtn = this._createIconButton('emblem-system-symbolic');
        Tooltip.attachTooltip(this._settingsBtn, () => _('Settings'));
        actionBox.add_child(this._clearBtn);
        actionBox.add_child(this._settingsBtn);
        mainBox.add_child(actionBox);
        this._enableBtn = new PopupMenu.PopupSwitchMenuItem(_('Capture'), true);
        this._enableBtn.connect('toggled', (_item, _state) => {
        });
        actionBox.add_child(this._enableBtn);
        this.add_child(mainBox);
    }
    _createIconButton(iconName, extraClass = '') {
        return new St.Button({
            style_class: `action-btn ${extraClass}`,
            child: new St.Icon({
                icon_name: iconName,
                icon_size: 16,
            }),
            can_focus: true,
            track_hover: true,
        });
    }
    enableNextButton(enable) {
        this._nextBtn.reactive = enable;
        this._nextBtn.opacity = enable ? 255 : 100;
    }
    enablePrevButton(enable) {
        this._prevBtn.reactive = enable;
        this._prevBtn.opacity = enable ? 255 : 100;
    }
    onNextItem(callback) {
        this._nextBtn.connect('clicked', callback);
    }
    onPrevItem(callback) {
        this._prevBtn.connect('clicked', callback);
    }
    onClearHistory(callback) {
        this._clearBtn.connect('clicked', callback);
    }
    onOpenSettings(callback) {
        this._settingsBtn.connect('clicked', callback);
    }
    enable() {
        return this._enableBtn ? !!this._enableBtn.state : true;
    }
    toggleCapture() {
        this._enableBtn.toggle();
        return !!this._enableBtn.state;
    }
}
