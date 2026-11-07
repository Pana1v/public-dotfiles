import St from 'gi://St';
import GObject from 'gi://GObject';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
let _ = (s) => s;
export function init(gettextFunc) {
    _ = gettextFunc;
}
export class SearchBox extends PopupMenu.PopupBaseMenuItem {
    searchEntry;
    static {
        GObject.registerClass(this);
    }
    constructor() {
        super({
            reactive: false,
            can_focus: false,
            style_class: 'search-box-container'
        });
        this.searchEntry = new St.Entry({
            style_class: 'search-box',
            can_focus: true,
            hint_text: _('Search clipboard...'),
            track_hover: true,
            x_expand: true,
        });
        let searchIcon = new St.Icon({
            icon_name: 'edit-find-symbolic',
            style_class: 'search-box-icon',
            icon_size: 16,
        });
        this.searchEntry.set_primary_icon(searchIcon);
        let clearIcon = new St.Icon({
            icon_name: 'edit-clear-symbolic',
            style_class: 'search-box-icon',
            icon_size: 16,
        });
        this.searchEntry.set_secondary_icon(clearIcon);
        this.searchEntry.connect('secondary-icon-clicked', () => {
            this.searchEntry.set_text('');
        });
        this.add_child(this.searchEntry);
    }
    onTextChanged(callback) {
        this.searchEntry.get_clutter_text().connect('text-changed', callback);
    }
    getText() {
        return this.searchEntry.get_text();
    }
    setText(text) {
        return this.searchEntry.set_text(text);
    }
}
