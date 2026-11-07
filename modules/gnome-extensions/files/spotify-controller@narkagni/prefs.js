import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';
import Gdk from 'gi://Gdk';
import Pango from 'gi://Pango';
import { ExtensionPreferences } from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

export default class SpotifyControllerPrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();

        // ============================================
        // PAGE 1: GENERAL (Panel Settings)
        // ============================================
        const generalPage = new Adw.PreferencesPage({
            title: 'General',
            icon_name: 'preferences-system-symbolic'
        });
        window.add(generalPage);

        const panelGroup = new Adw.PreferencesGroup();
        panelGroup.set_title('Top Panel Layout');
        generalPage.add(panelGroup);

        const posRow = new Adw.ComboRow({
            title: 'Panel Position',
            model: new Gtk.StringList({ strings: ['Left', 'Center (Before)', 'Center (After)', 'Right'] })
        });
        const posValues = ['left', 'center-before', 'center-after', 'right'];
        const currentPos = settings.get_string('position');
        posRow.selected = posValues.indexOf(currentPos) !== -1 ? posValues.indexOf(currentPos) : 2;
        posRow.connect('notify::selected', () => settings.set_string('position', posValues[posRow.selected]));
        panelGroup.add(posRow);

        const spacingRow = new Adw.SpinRow({
            title: 'Button Spacing',
            adjustment: new Gtk.Adjustment({ lower: 0, upper: 50, step_increment: 1 })
        });
        settings.bind('button-spacing', spacingRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        panelGroup.add(spacingRow);

        const marginRow = new Adw.SpinRow({
            title: 'Label Margin',
            adjustment: new Gtk.Adjustment({ lower: 0, upper: 100, step_increment: 1 })
        });
        settings.bind('label-margin', marginRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        panelGroup.add(marginRow);

        const toggleGroup = new Adw.PreferencesGroup();
        toggleGroup.set_title('Visibility Toggles');
        generalPage.add(toggleGroup);
        toggleGroup.add(this._createToggle(settings, 'show-prev', 'Show Previous Button'));
        toggleGroup.add(this._createToggle(settings, 'show-play-pause', 'Show Play/Pause Button'));
        toggleGroup.add(this._createToggle(settings, 'show-next', 'Show Next Button'));
        toggleGroup.add(this._createToggle(settings, 'show-panel-title', 'Show Song Title'));
        toggleGroup.add(this._createToggle(settings, 'show-panel-artist', 'Show Artist Name'));


        // ============================================
        // PAGE 2: CUSTOMIZATIONS (Visuals)
        // ============================================
        const visualPage = new Adw.PreferencesPage({
            title: 'Customizations',
            icon_name: 'preferences-desktop-theme-symbolic'
        });
        window.add(visualPage);

        // --- Group: Header Text ---
        const headerGroup = new Adw.PreferencesGroup();
        headerGroup.set_title('Header Settings');
        visualPage.add(headerGroup);

        const headerEntry = new Adw.EntryRow({
            title: 'Popup Header Text',
            text: settings.get_string('custom-header-text')
        });
        headerEntry.connect('apply', () => { settings.set_string('custom-header-text', headerEntry.text); });
        settings.bind('custom-header-text', headerEntry, 'text', Gio.SettingsBindFlags.DEFAULT);
        headerGroup.add(headerEntry);

        const headerSizeRow = new Adw.SpinRow({
            title: 'Header Font Size',
            adjustment: new Gtk.Adjustment({ lower: 8, upper: 30, step_increment: 1 })
        });
        settings.bind('header-font-size', headerSizeRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        headerGroup.add(headerSizeRow);

        const headerColorRow = new Adw.ActionRow({ title: 'Header Text Color' });
        headerColorRow.add_suffix(this._createColorButton(settings, 'header-text-color', '#ffffff'));
        headerGroup.add(headerColorRow);

        // --- Group: Popup Background ---
        const bgGroup = new Adw.PreferencesGroup();
        bgGroup.set_title('Popup Background');
        visualPage.add(bgGroup);

        const bgModeRow = new Adw.ComboRow({
            title: 'Background Mode',
            model: new Gtk.StringList({ strings: ['Ambient (Cover Art)', 'Custom Color'] })
        });
        
        const bgModes = ['ambient', 'custom'];
        let currentMode = 'ambient';
        try { currentMode = settings.get_string('bg-mode'); } catch(e) {}
        bgModeRow.selected = bgModes.indexOf(currentMode) !== -1 ? bgModes.indexOf(currentMode) : 0;
        bgGroup.add(bgModeRow);

        const customColorRow = new Adw.ActionRow({ title: 'Custom Background Color' });
        customColorRow.add_suffix(this._createColorButton(settings, 'custom-bg-color', '#2e3440'));
        bgGroup.add(customColorRow);

        const updateBgVisibility = () => {
            const selectedIndex = bgModeRow.selected;
            customColorRow.visible = (selectedIndex === 1);
            if (settings.get_string('bg-mode') !== bgModes[selectedIndex]) {
                settings.set_string('bg-mode', bgModes[selectedIndex]);
            }
        };
        bgModeRow.connect('notify::selected', updateBgVisibility);
        updateBgVisibility();

        // --- Group: Lyrics Customization ---
        const lyricsGroup = new Adw.PreferencesGroup();
        lyricsGroup.set_title('Lyrics Appearance');
        visualPage.add(lyricsGroup);

        // Active Line
        const lyricActiveColor = new Adw.ActionRow({ title: 'Active Line Color' });
        lyricActiveColor.add_suffix(this._createColorButton(settings, 'lyrics-active-color', '#ffffff'));
        lyricsGroup.add(lyricActiveColor);

        const lyricActiveSize = new Adw.SpinRow({
            title: 'Active Line Size',
            adjustment: new Gtk.Adjustment({ lower: 10, upper: 40, step_increment: 1 })
        });
        settings.bind('lyrics-active-size', lyricActiveSize, 'value', Gio.SettingsBindFlags.DEFAULT);
        lyricsGroup.add(lyricActiveSize);

        // Neighbor Line (Near active)
        const lyricNeighborColor = new Adw.ActionRow({ title: 'Neighbor Line Color' });
        lyricNeighborColor.add_suffix(this._createColorButton(settings, 'lyrics-neighbor-color', 'rgba(255,255,255,0.6)'));
        lyricsGroup.add(lyricNeighborColor);

        const lyricNeighborSize = new Adw.SpinRow({
            title: 'Neighbor Line Size',
            adjustment: new Gtk.Adjustment({ lower: 8, upper: 30, step_increment: 1 })
        });
        settings.bind('lyrics-neighbor-size', lyricNeighborSize, 'value', Gio.SettingsBindFlags.DEFAULT);
        lyricsGroup.add(lyricNeighborSize);

        // Inactive Line
        const lyricInactiveColor = new Adw.ActionRow({ title: 'Inactive Line Color' });
        lyricInactiveColor.add_suffix(this._createColorButton(settings, 'lyrics-inactive-color', 'rgba(255,255,255,0.25)'));
        lyricsGroup.add(lyricInactiveColor);

        const lyricInactiveSize = new Adw.SpinRow({
            title: 'Inactive Line Size',
            adjustment: new Gtk.Adjustment({ lower: 8, upper: 30, step_increment: 1 })
        });
        settings.bind('lyrics-inactive-size', lyricInactiveSize, 'value', Gio.SettingsBindFlags.DEFAULT);
        lyricsGroup.add(lyricInactiveSize);

        // Spacing
        const lyricSpacingRow = new Adw.SpinRow({
            title: 'Line Spacing',
            adjustment: new Gtk.Adjustment({ lower: 0, upper: 50, step_increment: 1 })
        });
        settings.bind('lyrics-line-spacing', lyricSpacingRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        lyricsGroup.add(lyricSpacingRow);


        // --- Group: Sizing & Radius ---
        const sizeGroup = new Adw.PreferencesGroup();
        sizeGroup.set_title('Cover Art & Controls');
        visualPage.add(sizeGroup);

        const artSizeRow = new Adw.SpinRow({
            title: 'Cover Art Size (px)',
            adjustment: new Gtk.Adjustment({ lower: 200, upper: 500, step_increment: 10 })
        });
        settings.bind('cover-art-size', artSizeRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        sizeGroup.add(artSizeRow);

        const radiusRow = new Adw.SpinRow({
            title: 'Corner Roundness',
            adjustment: new Gtk.Adjustment({ lower: 0, upper: 170, step_increment: 1 })
        });
        settings.bind('cover-art-radius', radiusRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        sizeGroup.add(radiusRow);

        const rotateRow = new Adw.SpinRow({
            title: 'Vinyl Rotation Speed',
            subtitle: 'Visible only when Roundness is 170', 
            adjustment: new Gtk.Adjustment({ lower: 0, upper: 50, step_increment: 1 }) 
        });
        try { settings.bind('art-rotate-speed', rotateRow, 'value', Gio.SettingsBindFlags.DEFAULT); } catch(e) {}
        sizeGroup.add(rotateRow);

        const updateEasterEgg = () => { rotateRow.visible = (radiusRow.value >= 170); };
        radiusRow.connect('notify::value', updateEasterEgg);
        updateEasterEgg();

        const btnSizeRow = new Adw.SpinRow({
            title: 'Control Button Size',
            adjustment: new Gtk.Adjustment({ lower: 16, upper: 32, step_increment: 1 })
        });
        settings.bind('popup-icon-size', btnSizeRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        sizeGroup.add(btnSizeRow);


        // --- Group: Typography & Colors ---
        const fontGroup = new Adw.PreferencesGroup();
        fontGroup.set_title('Fonts & Text Colors');
        visualPage.add(fontGroup);

        const fontRow = new Adw.ActionRow({ title: 'Global Font Family' });
        const fontDialog = new Gtk.FontDialog();
        const fontBtn = new Gtk.FontDialogButton({ dialog: fontDialog, valign: Gtk.Align.CENTER });
        const savedFont = settings.get_string('custom-font-family');
        if (savedFont) { try { fontBtn.set_font_desc(Pango.FontDescription.from_string(savedFont)); } catch(e) {} }
        fontBtn.connect('notify::font-desc', () => {
            const desc = fontBtn.get_font_desc();
            if (desc) settings.set_string('custom-font-family', desc.get_family());
        });
        fontRow.add_suffix(fontBtn);
        fontGroup.add(fontRow);

        const titleSizeRow = new Adw.SpinRow({ title: 'Song Title Size', adjustment: new Gtk.Adjustment({ lower: 8, upper: 40, step_increment: 1 }) });
        settings.bind('title-font-size', titleSizeRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        fontGroup.add(titleSizeRow);

        const titleColorRow = new Adw.ActionRow({ title: 'Song Title Color' });
        titleColorRow.add_suffix(this._createColorButton(settings, 'title-text-color', '#ffffff'));
        fontGroup.add(titleColorRow);

        const artistSizeRow = new Adw.SpinRow({ title: 'Artist Size', adjustment: new Gtk.Adjustment({ lower: 8, upper: 30, step_increment: 1 }) });
        settings.bind('artist-font-size', artistSizeRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        fontGroup.add(artistSizeRow);

        const artistColorRow = new Adw.ActionRow({ title: 'Artist Color' });
        artistColorRow.add_suffix(this._createColorButton(settings, 'artist-text-color', '#cccccc'));
        fontGroup.add(artistColorRow);

        const timeSizeRow = new Adw.SpinRow({ title: 'Time Duration Size', adjustment: new Gtk.Adjustment({ lower: 8, upper: 24, step_increment: 1 }) });
        settings.bind('time-font-size', timeSizeRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        fontGroup.add(timeSizeRow);

        const timeColorRow = new Adw.ActionRow({ title: 'Time Duration Color' });
        timeColorRow.add_suffix(this._createColorButton(settings, 'time-text-color', '#ffffff'));
        fontGroup.add(timeColorRow);
        
        const btnColorRow = new Adw.ActionRow({ title: 'Media Buttons Color' });
        btnColorRow.add_suffix(this._createColorButton(settings, 'popup-button-color', '#ffffff'));
        fontGroup.add(btnColorRow);


        // --- Group: Slider ---
        const sliderGroup = new Adw.PreferencesGroup();
        sliderGroup.set_title('Slider Customization');
        visualPage.add(sliderGroup);

        const styleRow = new Adw.ComboRow({
            title: 'Slider Style',
            model: new Gtk.StringList({ strings: ['Wavy', 'Straight'] })
        });
        const styleValues = ['wavy', 'straight'];
        const currentStyle = settings.get_string('slider-style');
        styleRow.selected = styleValues.indexOf(currentStyle) !== -1 ? styleValues.indexOf(currentStyle) : 0;
        styleRow.connect('notify::selected', () => {
            settings.set_string('slider-style', styleValues[styleRow.selected]);
            updateSpeedVisibility();
        });
        sliderGroup.add(styleRow);

        const speedRow = new Adw.SpinRow({
            title: 'Wave Speed',
            adjustment: new Gtk.Adjustment({ lower: 0.01, upper: 0.2, step_increment: 0.01 }),
            digits: 2
        });
        settings.bind('wave-speed', speedRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        sliderGroup.add(speedRow);

        const updateSpeedVisibility = () => { speedRow.visible = (styleValues[styleRow.selected] === 'wavy'); };
        updateSpeedVisibility();

        const thickRow = new Adw.SpinRow({
            title: 'Line Thickness',
            adjustment: new Gtk.Adjustment({ lower: 1, upper: 10, step_increment: 1 })
        });
        settings.bind('slider-thickness', thickRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        sliderGroup.add(thickRow);

        // THUMB SETTINGS
        const thumbRow = new Adw.ComboRow({
            title: 'Thumb Shape',
            model: new Gtk.StringList({ strings: ['Round Circle', 'Vertical Line'] })
        });
        const thumbValues = ['round', 'vertical'];
        const currentThumb = settings.get_string('thumb-style');
        const selIdx = thumbValues.indexOf(currentThumb);
        thumbRow.selected = selIdx !== -1 ? selIdx : 0;
        
        thumbRow.connect('notify::selected', () => {
            settings.set_string('thumb-style', thumbValues[thumbRow.selected]);
            updateThumbUI();
        });
        sliderGroup.add(thumbRow);

        const thumbSizeRow = new Adw.SpinRow({
            title: 'Thumb Size', 
            adjustment: new Gtk.Adjustment({ lower: 4, upper: 30, step_increment: 1 })
        });
        settings.bind('thumb-size', thumbSizeRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        sliderGroup.add(thumbSizeRow);

        const thumbThicknessRow = new Adw.SpinRow({
            title: 'Vertical Thickness',
            adjustment: new Gtk.Adjustment({ lower: 2, upper: 15, step_increment: 1 })
        });
        settings.bind('thumb-vertical-thickness', thumbThicknessRow, 'value', Gio.SettingsBindFlags.DEFAULT);
        sliderGroup.add(thumbThicknessRow);

        const updateThumbUI = () => {
            const style = thumbValues[thumbRow.selected];
            if (style === 'round') {
                thumbSizeRow.visible = true; thumbSizeRow.title = "Thumb Radius"; thumbThicknessRow.visible = false;
            } else {
                thumbSizeRow.visible = true; thumbSizeRow.title = "Thumb Height"; thumbThicknessRow.visible = true;
            }
        };
        updateThumbUI();

        const sliderColorRow = new Adw.ActionRow({ title: 'Active Line Color' });
        sliderColorRow.add_suffix(this._createColorButton(settings, 'slider-color', '#ffffff'));
        sliderGroup.add(sliderColorRow);

        const trackColorRow = new Adw.ActionRow({ title: 'Track (Background) Color' });
        trackColorRow.add_suffix(this._createColorButton(settings, 'slider-track-color', 'rgba(255, 255, 255, 0.3)'));
        sliderGroup.add(trackColorRow);

        const thumbColorRow = new Adw.ActionRow({ title: 'Thumb Color' });
        thumbColorRow.add_suffix(this._createColorButton(settings, 'thumb-color', '#ffffff'));
        sliderGroup.add(thumbColorRow);


        // ============================================
        // PAGE 3: PADDINGS
        // ============================================
        const paddingPage = new Adw.PreferencesPage({
            title: 'Paddings',
            icon_name: 'view-fullscreen-symbolic'
        });
        window.add(paddingPage);

        paddingPage.add(this._createPaddingGroup(settings, '1. Cover Art Padding', 'art-pad', true));
        paddingPage.add(this._createPaddingGroup(settings, '2. Text Info Margin', 'text-margin', true));
        paddingPage.add(this._createPaddingGroup(settings, '3. Slider Padding', 'slider-pad', true)); 
        paddingPage.add(this._createPaddingGroup(settings, '4. Media Buttons Padding', 'ctrl-pad', true)); 

    }

    _createPaddingGroup(settings, title, prefix, includeSides) {
        const group = new Adw.PreferencesGroup();
        group.set_title(title);
        const directions = includeSides ? ['Top', 'Bottom', 'Left', 'Right'] : ['Top', 'Bottom'];
        
        directions.forEach(dir => {
            const key = `${prefix}-${dir.toLowerCase()}`;
            const row = new Adw.SpinRow({
                title: `${dir} Spacing`,
                adjustment: new Gtk.Adjustment({ lower: 0, upper: 150, step_increment: 1 })
            });
            try { settings.bind(key, row, 'value', Gio.SettingsBindFlags.DEFAULT); } catch(e) {}
            group.add(row);
        });
        return group;
    }

    _createColorButton(settings, key, defaultHex) {
        const dialog = new Gtk.ColorDialog();
        const btn = new Gtk.ColorDialogButton({ dialog: dialog });
        const rgba = new Gdk.RGBA();
        let savedColor = defaultHex;
        try { savedColor = settings.get_string(key); } catch(e) {}
        if (!savedColor || !rgba.parse(savedColor)) rgba.parse(defaultHex);
        btn.set_rgba(rgba);
        btn.connect('notify::rgba', () => {
            settings.set_string(key, btn.get_rgba().to_string());
        });
        return btn;
    }

    _createToggle(settings, key, title) {
        const row = new Adw.SwitchRow({ title: title });
        settings.bind(key, row, 'active', Gio.SettingsBindFlags.DEFAULT);
        return row;
    }
}