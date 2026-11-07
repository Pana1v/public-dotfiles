export var LOG_LEVELS;
(function (LOG_LEVELS) {
    LOG_LEVELS[LOG_LEVELS["OFF"] = 0] = "OFF";
    LOG_LEVELS[LOG_LEVELS["ERROR"] = 1] = "ERROR";
    LOG_LEVELS[LOG_LEVELS["WARN"] = 2] = "WARN";
    LOG_LEVELS[LOG_LEVELS["INFO"] = 3] = "INFO";
    LOG_LEVELS[LOG_LEVELS["DEBUG"] = 4] = "DEBUG";
})(LOG_LEVELS || (LOG_LEVELS = {}));
let _settings = null;
export function init(settings) {
    _settings = settings;
}
export function log_level() {
    if (!_settings)
        return LOG_LEVELS.INFO;
    return _settings.get_uint('log-level');
}
export function log(text) {
    console.log(`Gnome Clipboard: ${text}`);
}
export function error(text) {
    if (log_level() >= LOG_LEVELS.ERROR)
        console.error(`Gnome Clipboard: [ERROR] ${text}`);
}
export function warn(text) {
    if (log_level() >= LOG_LEVELS.WARN)
        console.warn(`Gnome Clipboard: [WARN] ${text}`);
}
export function info(text) {
    if (log_level() >= LOG_LEVELS.INFO)
        console.info(`Gnome Clipboard: [INFO] ${text}`);
}
export function debug(text) {
    if (log_level() >= LOG_LEVELS.DEBUG)
        console.debug(`Gnome Clipboard: [DEBUG] ${text}`);
}
