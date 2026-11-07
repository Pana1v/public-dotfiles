import St from 'gi://St';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as log from './log.js';
export class ScrollMenu extends PopupMenu.PopupMenuSection {
    scrollView;
    scrollViewSection;
    constructor() {
        super();
        this.scrollView = new St.ScrollView({
            overlay_scrollbars: true,
            style_class: "scroll-view",
            clip_to_allocation: true,
        });
        this.scrollView.set_policy(St.PolicyType.NEVER, St.PolicyType.AUTOMATIC);
        this.scrollViewSection = new PopupMenu.PopupMenuSection();
        this.scrollView.add_child(this.scrollViewSection.actor);
        this.actor.add_child(this.scrollView);
    }
    filterItems(query) {
        log.debug(`filtering ${query}`);
        let items = this.scrollViewSection._getMenuItems();
        if (query === '') {
            items.forEach(function (item) {
                item.actor.visible = true;
            });
        }
        else {
            items.forEach(function (item) {
                let text = item.text().toLowerCase();
                let matched = text.indexOf(query) >= 0;
                item.actor.visible = matched;
            });
        }
    }
    addMenuItem(item) {
        this.scrollViewSection.addMenuItem(item);
    }
    removeAll() {
        this.scrollViewSection.removeAll();
    }
    scrollToBottom() {
    }
}
;
