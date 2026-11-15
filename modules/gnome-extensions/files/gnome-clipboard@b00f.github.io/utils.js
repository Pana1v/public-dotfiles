import GObject from 'gi://GObject';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
const FNV_OFFSET = 0x811c9dc5;
const FNV_PRIME = 0x01000193;
function fnv1a32(data) {
    let hash = FNV_OFFSET;
    for (let i = 0; i < data.length; i++) {
        hash ^= data[i];
        hash = Math.imul(hash, FNV_PRIME);
    }
    return hash >>> 0;
}
export function hashByte(bytes) {
    const data = bytes?.get_data?.();
    return data ? fnv1a32(data) : FNV_OFFSET;
}
export function hashText(text) {
    return fnv1a32(new TextEncoder().encode(text));
}
export function truncate(text, length) {
    text = text.trim();
    text = text.replace(/\s+/g, ' ');
    if (text.length > length) {
        text = text.substring(0, length - 1) + '...';
    }
    return text;
}
const hasBoxOrientation = GObject.Object.find_property.call(St.BoxLayout, 'orientation') !== null;
export function boxOrientation(orientation) {
    if (hasBoxOrientation) {
        return { orientation };
    }
    return { vertical: orientation === Clutter.Orientation.VERTICAL };
}
