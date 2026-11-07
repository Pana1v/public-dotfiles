import Adw from 'gi://Adw';
import GObject from 'gi://GObject';

export var DependencyErrorPage = GObject.registerClass(
class LLSDependencyErrorPage extends Adw.PreferencesPage {
    _init() {
        super._init({
            title: 'Setup Required',
            icon_name: 'dialog-warning-symbolic',
            name: 'DependencyErrorPage',
        });

        const group = new Adw.PreferencesGroup({
            title: 'MPV is not installed',
            description:
                'Live Lock Screen uses MPV to play media on your lock screen. ' +
                'Install it with your package manager, then reopen this window.',
        });

        const mpvRow = new Adw.ActionRow({
            title: 'Install MPV',
            subtitle:
                `  • Fedora/RHEL: sudo dnf install mpv\n` +
                `  • Ubuntu/Debian: sudo apt install mpv\n` +
                `  • Arch: sudo pacman -S mpv`,
            icon_name: 'system-software-install-symbolic',
        });
        mpvRow.add_css_class('accent');

        group.add(mpvRow);
        this.add(group);
    }
});