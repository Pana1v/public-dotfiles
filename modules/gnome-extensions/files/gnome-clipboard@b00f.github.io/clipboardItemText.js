import St from 'gi://St';
import Clutter from 'gi://Clutter';
import * as utils from './utils.js';
import { ClipboardItem, ClipboardItemType } from './clipboardItem.js';
export class ClipboardItemText extends ClipboardItem {
    type = ClipboardItemType.TEXT;
    text;
    constructor(id, text) {
        super(id);
        this.text = text;
    }
    notification() {
        return utils.truncate(this.text, 32);
    }
    displayWidget() {
        const label = new St.Label({
            text: this.notification(),
            style_class: 'clipboard-item-text',
            x_align: Clutter.ActorAlign.START,
        });
        label.clutter_text.line_wrap = true;
        return label;
    }
    searchText() {
        return this.text;
    }
    async copyToClipboard() {
        const clipboard = St.Clipboard.get_default();
        clipboard.set_text(St.ClipboardType.CLIPBOARD, this.text);
    }
    dispose(_store) {
    }
    toJSON() {
        return {
            type: this.type,
            id: this.id,
            text: this.text,
            pinned: this.pinned,
            copiedAt: this.copiedAt,
            usage: this.usage,
            usedAt: this.usedAt,
        };
    }
    static fromJSON(raw) {
        const item = new ClipboardItemText(raw.id, raw.text);
        item.pinned = raw.pinned;
        item.copiedAt = raw.copiedAt;
        item.usage = raw.usage;
        item.usedAt = raw.usedAt;
        return item;
    }
}
ClipboardItem.registerType(ClipboardItemType.TEXT, ClipboardItemText.fromJSON);
