import * as utils from './utils.js';
export var ClipboardItemType;
(function (ClipboardItemType) {
    ClipboardItemType[ClipboardItemType["TEXT"] = 0] = "TEXT";
    ClipboardItemType[ClipboardItemType["IMAGE"] = 1] = "IMAGE";
})(ClipboardItemType || (ClipboardItemType = {}));
function imageID(path) {
    const name = path.slice(path.lastIndexOf('/') + 1);
    const match = name.match(/^(-?\d+)\.png$/);
    return match ? Number(match[1]) : utils.hashCode(path);
}
export class ClipboardItem {
    text;
    usage;
    pinned;
    copiedAt;
    usedAt;
    type;
    imagePath;
    _id = null;
    constructor(text, usage, pinned, copiedAt, usedAt, type = ClipboardItemType.TEXT, imagePath = null) {
        this.text = text;
        this.usage = usage;
        this.pinned = pinned;
        this.copiedAt = copiedAt;
        this.usedAt = usedAt;
        this.type = type;
        this.imagePath = imagePath;
    }
    id() {
        if (this._id === null) {
            this._id = (this.type === ClipboardItemType.IMAGE && this.imagePath)
                ? imageID(this.imagePath)
                : utils.hashCode(this.text);
        }
        return this._id;
    }
    display() {
        if (this.type === ClipboardItemType.IMAGE) {
            return "[Image]";
        }
        return utils.truncate(this.text, 32);
    }
    updateLastUsed() {
        this.usage++;
        this.usedAt = Date.now();
    }
}
