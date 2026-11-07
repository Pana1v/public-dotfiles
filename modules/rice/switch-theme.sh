#!/usr/bin/env bash
# Switch the whole rice to another palette: ./switch-theme.sh matrix
#
#   themes/<name>.palette   role -> hex, plus @settings (gtk, vscode, btop, ...)
#   current-theme           which palette the files hold right now
#
# Every themed file is rewritten in place, swapping each hex of the current
# palette for the same role's hex in the target. Hexes are unique per palette,
# so the swap runs both ways without loss.
set -euo pipefail
MOD="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$(cd "$MOD/../.." && pwd)"
TARGET="${1:?usage: switch-theme.sh <$(ls "$MOD/themes" | sed 's/.palette//' | paste -sd'|')>}"
CURRENT="$(cat "$MOD/current-theme")"
# shellcheck source=../../lib/common.sh
. "$DOTFILES/lib/common.sh"

[ -f "$MOD/themes/$TARGET.palette" ] || { echo "no palette: themes/$TARGET.palette" >&2; exit 1; }

# Same theme: skip the recolor, just re-apply its settings (apply.sh does this).
if [ "$TARGET" != "$CURRENT" ]; then
    # Files that carry palette hexes. Theme-specific files (btop/*.theme) stay out.
    FILES=(
        "$MOD"/files/claude/rice.json
        "$MOD"/files/kitty/current-theme.conf
        "$MOD"/files/starship.toml
        "$MOD"/files/fzf.sh
        "$MOD"/files/gtk-4.0/gtk.css
        "$MOD"/files/gtk-3.0/gtk.css
        "$MOD"/files/gnome-shell/gnome-shell.css
        "$MOD"/files/gnome-shell/brackets.svg
        "$MOD"/files/gnome-shell/brackets-sm.svg
        "$MOD"/files/tmux/tokyonight.conf
        "$MOD"/files/cava/config
        "$MOD"/files/blerc
        "$MOD"/files/rofi/rice.rasi
        "$MOD"/files/qt5ct/colors/rice.conf
        "$MOD"/files/kdeglobals
        "$MOD"/files/obsidian/theme.css
        "$DOTFILES"/modules/conky/files/conky/*/*.lua
        "$DOTFILES"/modules/conky/files/conky/Elysium/modules/*/module.lua
        "$DOTFILES"/modules/terminator/files/config
        "$DOTFILES"/modules/cli-tools/files/lazygit.yml
        "$MOD"/files/ptyxis/rice.palette
        "$DOTFILES"/modules/gnome-extensions/files/sysmon-flair@pan.local/stylesheet.css
    )

    python3 - "$MOD/themes/$CURRENT.palette" "$MOD/themes/$TARGET.palette" "${FILES[@]}" <<'EOF'
import re, sys

def palette(path):
    roles = {}
    for line in open(path):
        parts = line.split()
        if len(parts) < 2 or parts[0].startswith(("#", "@")):
            continue
        roles[parts[0]] = parts[1].lower()
    return roles

src, dst = palette(sys.argv[1]), palette(sys.argv[2])
assert src.keys() == dst.keys(), f"role sets differ: {src.keys() ^ dst.keys()}"
for name, p in (("current", src), ("target", dst)):
    dupes = {v for v in p.values() if list(p.values()).count(v) > 1}
    assert not dupes, f"{name} palette reuses {dupes}; switching back would be lossy"

swap = {src[r]: dst[r] for r in src}
pattern = re.compile("|".join(map(re.escape, swap)), re.IGNORECASE)
for path in sys.argv[3:]:
    text = open(path).read()
    new = pattern.sub(lambda m: swap[m.group(0).lower()], text)
    if new != text:
        open(path, "w").write(new)
        print(f"    recolor {path}")
EOF
fi

echo "$TARGET" > "$MOD/current-theme"

# Runtime copy for things that read colours live (sysmon-flair's load ramp,
# top bar line and window strip). They watch this file, so no re-login.
mkdir -p "$HOME/.config/rice"
cp "$MOD/themes/$TARGET.palette" "$HOME/.config/rice/palette"

# sysmon-flair is copied, not linked (gnome-extensions module), so push the
# recoloured stylesheet and toggle the extension to reload it.
SYSMON=sysmon-flair@pan.local
SYSMON_DIR="$HOME/.local/share/gnome-shell/extensions/$SYSMON"
if [ -d "$SYSMON_DIR" ]; then
    cp "$DOTFILES/modules/gnome-extensions/files/$SYSMON/stylesheet.css" "$SYSMON_DIR/"
    if gnome-extensions info "$SYSMON" 2>/dev/null | grep -q "Enabled: Yes"; then
        gnome-extensions disable "$SYSMON" && gnome-extensions enable "$SYSMON"
    fi
fi

# ---- Settings that are names, not hexes --------------------------------
setting() { sed -n "s/^@$1[[:space:]]\+//p" "$MOD/themes/$TARGET.palette"; }

# Zorin theme and schema names become their stand-ins elsewhere (zorin-deps.txt).
GTK="$(distro_name theme "$(setting gtk)")"
gsettings set org.gnome.desktop.interface gtk-theme "$GTK"
# @cursor Rice-cursors: the Oreo cursors recoloured to the palette accent,
# built here (like the Rice icons) so every palette gets a matching cursor.
CURSOR="$(setting cursor)"
if [ "$CURSOR" = Rice-cursors ]; then
    python3 -I "$MOD/tools/rice-cursors.py" "$MOD/themes/$TARGET.palette" \
        "$DOTFILES/modules/fonts-cursors/files/icons/oreo-pink-cursors"
fi
gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR"
# @accent is optional: GNOME's own accent (blue, teal, green, ...), seen by apps
# that ignore gtk.css, e.g. Settings and flatpaks.
ACCENT="$(setting accent)"
[ -n "$ACCENT" ] && gsettings set org.gnome.desktop.interface accent-color "$ACCENT"
# @shell is optional: palettes without one use their GTK theme's shell.
SHELL_THEME="$(setting shell)"
gsettings set org.gnome.shell.extensions.user-theme name "${SHELL_THEME:-$GTK}"
has_schema() { gsettings list-keys "$1" >/dev/null 2>&1 || { echo "    skip    $1: not installed"; return 1; }; }

TB=org.gnome.shell.extensions.zorin-taskbar
if has_schema $TB; then
    gsettings set $TB trans-border-custom-color "$(setting taskbar_border)"
fi

# Dock paints its background inline, so the shell CSS can't reach it.
# Same fill and alpha as the conky cards (flat.lua CARD_ALPHA), square corners.
DOCK=org.gnome.shell.extensions.$(distro_name dconf zorin-dash)
if has_schema $DOCK; then
    gsettings set $DOCK custom-background-color true
    gsettings set $DOCK background-color "$(sed -n 's/^bg[[:space:]]\+//p' "$MOD/themes/$TARGET.palette")"
    gsettings set $DOCK transparency-mode 'FIXED'
    gsettings set $DOCK background-opacity 0.78
    gsettings set $DOCK force-straight-corner true
fi

# Music pill (dock/panel media widget) also styles itself inline; it takes R,G,B.
role() { sed -n "s/^$1[[:space:]]\\+#//p" "$MOD/themes/$TARGET.palette"; }
rgb() { local h; h="$(role "$1")"; printf '%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }
PILL=org.gnome.shell.extensions.dynamic-music-pill
PILL_SCHEMAS="$HOME/.local/share/gnome-shell/extensions/dynamic-music-pill@andbal/schemas"
pill() { gsettings --schemadir "$PILL_SCHEMAS" set $PILL "$@"; }
# Not shipped by this repo, so skip it rather than abort the theme switch.
if [ -d "$PILL_SCHEMAS" ]; then
    pill use-custom-colors true
    pill custom-bg-color "$(rgb bg)"
    pill custom-text-color "$(rgb fg)"
    pill popup-follow-custom-bg true
    pill popup-follow-custom-text true
    pill border-radius 0
    pill popup-follow-radius true
    pill show-pill-border false
fi

WP="$(setting wallpaper)"
case "$WP" in
    image:*)
        uri="file://$HOME/.local/share/backgrounds/${WP#image:}"
        gsettings set org.gnome.desktop.background picture-options 'zoom'
        gsettings set org.gnome.desktop.background picture-uri "$uri"
        gsettings set org.gnome.desktop.background picture-uri-dark "$uri"
        ;;
    color:*)
        # picture-options none = no image, just primary-color.
        gsettings set org.gnome.desktop.background picture-options 'none'
        gsettings set org.gnome.desktop.background color-shading-type 'solid'
        gsettings set org.gnome.desktop.background primary-color "${WP#color:}"
        ;;
esac

# Icons: "Rice" is Papirus-Dark with folders recoloured to the accent, built
# from the palette (Papirus lives in /usr/share, so its folder links can't be
# re-pointed without root). Files, the app grid, rofi and Qt all use it.
if [ -d /usr/share/icons/Papirus-Dark ]; then
    python3 "$MOD/tools/folder-icons.py" "$MOD/themes/$TARGET.palette"
    gtk-update-icon-cache -q -f "$HOME/.local/share/icons/Rice" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme 'Rice'
else
    echo "    skip    Rice icons: Papirus-Dark not installed"
fi

mkdir -p "$HOME/.config/btop/themes"
for t in "$MOD"/files/btop/*.theme; do
    ln -sf "$t" "$HOME/.config/btop/themes/$(basename "$t")"
done
# Each config exists only once its app has run (or the vscode module linked it).
# --follow-symlinks: settings.json links into this repo; plain sed -i would
# replace the link with a copy.
BTOP_CONF="$HOME/.config/btop/btop.conf"
[ -f "$BTOP_CONF" ] && sed -i "s/^color_theme = .*/color_theme = \"$(setting btop)\"/" "$BTOP_CONF"
# Editors: regenerate the "Rice" theme from the new palette, then point VS Code
# and Cursor at @vscode (Rice for every palette). Reload the window to see it.
if [ -e "$HOME/.local/share/rice/vscode-rice" ]; then
    python3 -I "$MOD/tools/vscode-theme.py" "$MOD/themes/$TARGET.palette" "$HOME/.local/share/rice/vscode-rice"
    for d in "$HOME/.vscode/extensions/local.rice-0.1.0" "$HOME/.cursor/extensions/local.rice-0.1.0"; do
        [ -d "$d" ] && [ ! -L "$d" ] && rsync -a --delete "$HOME/.local/share/rice/vscode-rice/" "$d/"
    done
fi
for EDITOR_SETTINGS in "$HOME/.config/Code/User/settings.json" "$HOME/.config/Cursor/User/settings.json"; do
    [ -f "$EDITOR_SETTINGS" ] && sed -i --follow-symlinks \
        "s/\"workbench.colorTheme\": \"[^\"]*\"/\"workbench.colorTheme\": \"$(setting vscode)\"/" "$EDITOR_SETTINGS"
done

# Obsidian: the vault syncs through git (phone included), so the theme is
# copied in, not symlinked. Obsidian reloads a changed theme.css live.
VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/ObsidianNotes}"
if [ -d "$VAULT/.obsidian" ]; then
    mkdir -p "$VAULT/.obsidian/themes/Rice"
    cp "$MOD"/files/obsidian/{manifest.json,theme.css} "$VAULT/.obsidian/themes/Rice/"
    # An accentColor here is applied inline and would override the theme's accent.
    python3 - "$VAULT/.obsidian/appearance.json" <<'PY'
import json, os, sys
path = sys.argv[1]
conf = json.load(open(path)) if os.path.exists(path) else {}
conf.update(cssTheme="Rice", theme="obsidian", accentColor="")
with open(path, "w") as f:
    json.dump(conf, f, indent=2)
PY
fi

# Conky accent: a palette role name (default green, the widgets' live-state colour).
CONKY_ACCENT="$(setting conky_accent)"
sed -i "s/^M\.theme\.accent = .*/M.theme.accent = \"$(sed -n "s/^${CONKY_ACCENT:-green}[[:space:]]\+//p" "$MOD/themes/$TARGET.palette")\"/" \
    "$DOTFILES"/modules/conky/files/conky/Common/flat.lua

# Chrome: the unpacked "Rice" theme carries its colours as RGB lists, so it is
# rebuilt from the palette. Reload it in chrome://extensions (or restart Chrome).
CHROME_THEME="$HOME/.config/chrome-rice-theme"
if [ -f "$CHROME_THEME/manifest.json" ]; then
    python3 - "$MOD/themes/$TARGET.palette" "$CHROME_THEME/manifest.json" <<'PY'
import json, sys
roles = {}
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) > 1 and not p[0].startswith(("#", "@")):
        roles[p[0]] = [int(p[1][i:i + 2], 16) for i in (1, 3, 5)]
r = roles
conf = json.load(open(sys.argv[2]))
conf["description"] = "Matches the desktop rice palette."
conf["theme"]["colors"] = {
    "frame": r["black"], "frame_inactive": r["bg"], "frame_incognito": r["black"],
    "toolbar": r["bg"], "toolbar_button_icon": r["fg2"], "tab_text": r["fg"],
    "tab_background_text": r["dim2"], "bookmark_text": r["fg2"],
    "ntp_background": r["bg"], "ntp_text": r["fg"], "ntp_link": r["accent"],
    "button_background": r["surface"], "omnibox_background": r["surface"], "omnibox_text": r["fg"],
}
json.dump(conf, open(sys.argv[2], "w"), indent=2)
PY
    rm -f "$CHROME_THEME/Cached Theme.pak"
fi

# ---- Reload what can reload live ---------------------------------------
# Every running conky widget; the monitor watcher only restarts the others.
mapfile -t CONKYS < <(systemctl --user list-units --type=service --state=active --plain --no-legend '*conky*' | awk '{print $1}' | grep -v monitor-watch)
[ ${#CONKYS[@]} -gt 0 ] && systemctl --user restart "${CONKYS[@]}"
pkill -USR1 -x kitty 2>/dev/null || true
tmux source-file "$HOME/.tmux.conf" 2>/dev/null || true

# Every browser (Chromium family and Firefox family) and the start page,
# once the browsers module has been applied on this machine.
if [ -e "$HOME/.local/share/rice/startpage" ]; then
    DOTFILES="$DOTFILES" bash "$DOTFILES/modules/browsers/apply.sh" || true
fi

echo "now on $TARGET. Restart Terminator, Files, Claude Code and your browsers to see their new colors."
