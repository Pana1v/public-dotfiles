export var ClipboardItemType;
(function (ClipboardItemType) {
    ClipboardItemType[ClipboardItemType["TEXT"] = 0] = "TEXT";
    ClipboardItemType[ClipboardItemType["IMAGE"] = 1] = "IMAGE";
})(ClipboardItemType || (ClipboardItemType = {}));
export class ClipboardItem {
    id;
    pinned;
    usage;
    copiedAt;
    usedAt;
    constructor(id) {
        this.id = id;
        this.pinned = false;
        this.copiedAt = Date.now();
        this.usedAt = Date.now();
        this.usage = 1;
    }
    updateLastUsed() {
        this.usage++;
        this.usedAt = Date.now();
    }
    static _factories = new Map();
    static registerType(type, factory) {
        ClipboardItem._factories.set(type, factory);
    }
    static fromJSON(raw) {
        const type = raw?.type === ClipboardItemType.IMAGE
            ? ClipboardItemType.IMAGE
            : ClipboardItemType.TEXT;
        const factory = ClipboardItem._factories.get(type);
        if (!factory) {
            throw new Error(`no clipboard item registered for type ${type}`);
        }
        return factory(raw);
    }
}
