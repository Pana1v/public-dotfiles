import St from 'gi://St';
import GObject from 'gi://GObject';
import Clutter from 'gi://Clutter';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
let _ = (s) => s;
export function init(gettextFunc) {
    _ = gettextFunc;
}
export class ActionBar extends PopupMenu.PopupBaseMenuItem {
    _privateBtn;
    _pinBtn;
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
            style_class: 'action-bar',
        });
        let mainBox = new St.BoxLayout({
            orientation: Clutter.Orientation.HORIZONTAL,
            x_expand: true,
            style_class: 'action-bar-container'
        });
        let navBox = new St.BoxLayout({
            orientation: Clutter.Orientation.HORIZONTAL,
            style_class: 'nav-group'
        });
        this._prevBtn = this._createIconButton('go-previous-symbolic', _('Previous Item'));
        this._nextBtn = this._createIconButton('go-next-symbolic', _('Next Item'));
        navBox.add_child(this._prevBtn);
        navBox.add_child(this._nextBtn);
        mainBox.add_child(navBox);
        let spacer = new St.Widget({ x_expand: true });
        mainBox.add_child(spacer);
        let actionBox = new St.BoxLayout({
            orientation: Clutter.Orientation.HORIZONTAL,
            style_class: 'action-group'
        });
        this._privateBtn = this._createIconButton('view-conceal-symbolic', _('Private Mode'));
        this._pinBtn = this._createIconButton('view-pin-symbolic', _('Pin Current Item'));
        this._clearBtn = this._createIconButton('edit-delete-symbolic', _('Clear History'), 'action-btn-danger');
        this._settingsBtn = this._createIconButton('emblem-system-symbolic', _('Settings'));
        actionBox.add_child(this._privateBtn);
        actionBox.add_child(this._pinBtn);
        actionBox.add_child(this._clearBtn);
        actionBox.add_child(this._settingsBtn);
        mainBox.add_child(actionBox);
        this._enableBtn = new PopupMenu.PopupSwitchMenuItem(_("Service"), true);
        this._enableBtn.connect('toggled', (_item, _state) => {
        });
        actionBox.add_child(this._enableBtn);
        this.add_child(mainBox);
    }
    _createIconButton(iconName, tooltip, extraClass = '') {
        let button = new St.Button({
            style_class: `action-btn ${extraClass}`,
            child: new St.Icon({
                icon_name: iconName,
                icon_size: 16
            }),
            can_focus: true,
            track_hover: true,
        });
        button.set_accessible_name(tooltip);
        return button;
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
    onPin(callback) {
        this._pinBtn.connect('clicked', callback);
    }
    onTogglePrivateMode(callback) {
        this._privateBtn.connect('clicked', () => callback(true));
    }
    setPrivateMode(active) {
        if (active) {
            this._privateBtn.add_style_class_name('active-btn');
        }
        else {
            this._privateBtn.remove_style_class_name('active-btn');
        }
    }
    onOpenSettings(callback) {
        this._settingsBtn.connect('clicked', callback);
    }
    enable() {
        return this._enableBtn ? !!this._enableBtn.state : true;
    }
}
