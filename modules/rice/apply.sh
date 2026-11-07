#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/rice"
F="$MOD/files"

# Theme is a per-machine choice: RICE_THEME in the environment or in
# ~/.config/dotfiles/local.env (e.g. RICE_THEME=tron). Unset keeps whatever
# palette the repo files hold right now (current-theme).
: "${LOCAL_ENV:=$HOME/.config/dotfiles/local.env}"
if [ -z "${RICE_THEME:-}" ] && [ -f "$LOCAL_ENV" ]; then
    RICE_THEME="$(sed -n "s/^[[:space:]]*RICE_THEME[[:space:]]*=[[:space:]]*[\"']\?\([A-Za-z0-9_-]*\).*/\1/p" "$LOCAL_ENV" | tail -1)"
fi
THEME="${RICE_THEME:-$(cat "$MOD/current-theme")}"
[ -f "$MOD/themes/$THEME.palette" ] || { warn "no palette themes/$THEME.palette (have: $(ls "$MOD/themes" | sed 's/.palette//' | paste -sd' '))"; exit 1; }
log "theme   $THEME"
PALETTE="$MOD/themes/$THEME.palette"
setting() { sed -n "s/^@$1[[:space:]]\+//p" "$PALETTE"; }
# Zorin theme names become their stand-ins elsewhere (zorin-deps.txt).
GTK_THEME="$(distro_name theme "$(setting gtk)")"
GTK_REPO="https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme.git"
GTK_SRC="$HOME/.cache/dotfiles/Tokyonight-GTK-Theme"

# Skip apt when present: sudo has no tty when re-run from scripts.
dpkg -s sassc papirus-icon-theme rofi qalc xclip qt5ct node-typescript make >/dev/null 2>&1 || apt_install "$MOD/packages.apt"

# Set a gsettings key only when it differs, so re-runs print ok.
gset() {
    local schema="$1" key="$2" val="$3"
    if [ "$(gsettings get "$schema" "$key")" = "'$val'" ]; then
        log "ok      $schema $key"
        return 0
    fi
    run gsettings set "$schema" "$key" "$val"
    log "set     $schema $key = $val"
}

# ── GTK3 + GNOME Shell + libadwaita ────────────────────────────────────────
# Stock themes (e.g. mono's ZorinGrey-Dark, Yaru-dark on Ubuntu) ship in /usr/share/themes; only
# build Tokyonight when the palette's theme is installed nowhere.
if [ ! -d "$HOME/.themes/$GTK_THEME" ] && [ ! -d "/usr/share/themes/$GTK_THEME" ]; then
    # Sparse: only themes/ (skips ~40MB of icons). HTTP/1.1: HTTP/2 streams
    # were cancelled mid-clone on slow links.
    if [ ! -d "$GTK_SRC" ]; then
        run git -c http.version=HTTP/1.1 clone --depth 1 --filter=blob:none --sparse "$GTK_REPO" "$GTK_SRC"
        run git -C "$GTK_SRC" -c http.version=HTTP/1.1 sparse-checkout set themes
    fi
    case "$GTK_THEME" in
        *Green*) run "$GTK_SRC/themes/install.sh" -c dark -t green --tweaks black ;;
        *)       run "$GTK_SRC/themes/install.sh" -c dark ;;
    esac
fi
# Icon theme (Rice, built from Papirus-Dark) is set by switch-theme.sh.

# libadwaita apps ignore gtk-theme; they recolor from named colors in this file.
link_file "$F/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
# Titlebars for GTK3 apps (the gtk-theme draws the rest).
link_file "$F/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
# A Plasma session leaves Breeze colors, titlebar buttons and its own theme,
# cursor and icon names here, which beat the GNOME settings in GTK apps.
# Spotted by Breeze color names in colors.css; the other files come with it.
for dir in gtk-3.0 gtk-4.0; do
    grep -qs '_breeze' "$HOME/.config/$dir/colors.css" || continue
    for f in colors.css window_decorations.css assets settings.ini; do
        p="$HOME/.config/$dir/$f"
        [ -e "$p" ] || continue
        run mv "$p" "$p.bak.$TS"
        log "backup  $p.bak.$TS (Plasma leftover)"
    done
done
run gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Manrope Bold 10'

# Shell theme "Rice": the distro's dark shell theme plus the conky HUD look on
# notifications. gnome-shell.css imports base.css, written here per machine
# (gitignored) since the base theme's path differs between Zorin and Ubuntu.
BASE_SHELL="$(distro_name theme ZorinGrey-Dark)"
BASE_CSS="@import url(\"/usr/share/themes/$BASE_SHELL/gnome-shell/gnome-shell.css\");"
if [ "$(cat "$F/gnome-shell/base.css" 2>/dev/null)" != "$BASE_CSS" ]; then
    [ "$DRY_RUN" = 1 ] || echo "$BASE_CSS" > "$F/gnome-shell/base.css"
    log "write   gnome-shell/base.css ($BASE_SHELL)"
fi
link_file "$F/gnome-shell" "$HOME/.themes/Rice/gnome-shell"

# ── Tiling (pop-shell) ─────────────────────────────────────────────────────
# No apt package on noble, so build from source; master_noble targets GNOME
# 45+. Not `make local-install`: its configure step prompts and rewrites
# keybindings the gnome module owns, and gnome-extensions owns enabling.
POP_UUID="pop-shell@system76.com"
POP_REPO="https://github.com/pop-os/shell.git"
POP_BRANCH="master_noble"
POP_SRC="$HOME/.cache/dotfiles/pop-shell"
SHELL_MAJOR="$(gnome-shell --version 2>/dev/null | grep -o '[0-9]\+' | head -1 || true)"
if [ -d "$HOME/.local/share/gnome-shell/extensions/$POP_UUID" ] || [ -d "/usr/share/gnome-shell/extensions/$POP_UUID" ]; then
    log "ok      $POP_UUID"
elif [ "${SHELL_MAJOR:-0}" -lt 45 ]; then
    warn "pop-shell skipped: $POP_BRANCH needs GNOME 45+, found '${SHELL_MAJOR:-none}'"
elif [ "$DRY_RUN" != 1 ] && ! command -v tsc >/dev/null; then
    warn "pop-shell skipped: tsc missing (apt install node-typescript)"
else
    if [ ! -d "$POP_SRC" ]; then
        run git -c http.version=HTTP/1.1 clone --depth 1 --branch "$POP_BRANCH" "$POP_REPO" "$POP_SRC"
    fi
    if run make -C "$POP_SRC" depcheck compile install; then
        log "install $POP_UUID (log out and back in to load it)"
    else
        warn "pop-shell build failed, see output above"
    fi
fi

# Floating, translucent taskbar that turns opaque behind maximized windows.
TB=org.gnome.shell.extensions.zorin-taskbar
# Zorin only; it is off there too, and Ubuntu uses its dock instead.
if gsettings list-keys $TB >/dev/null 2>&1; then
    run gsettings set $TB panel-margin 8
    run gsettings set $TB global-border-radius 4
    run gsettings set $TB trans-use-custom-opacity true
    run gsettings set $TB trans-panel-opacity 0.7
    run gsettings set $TB trans-use-dynamic-opacity true
    run gsettings set $TB trans-dynamic-behavior "MAXIMIZED_WINDOWS"
    run gsettings set $TB trans-use-border true
    run gsettings set $TB trans-border-use-custom-color true
else
    log "skip    taskbar: $TB not installed (Zorin only)"
fi

# ── Wallpaper ──────────────────────────────────────────────────────────────
for w in "$F"/wallpaper/*; do link_file "$w" "$HOME/.local/share/backgrounds/$(basename "$w")"; done

# ── Avatar and lock screen ─────────────────────────────────────────────────
# The X avatar (tools/grid.py avatar) and a looping grid video for the
# live-lockscreen extension, rendered from the same grid as the wallpaper.
# GDM, Plymouth and the boot entries are root's job: sudo system-rice.sh.
# Avatar is drawn in the Ares palette; recolour it for this machine's.
AV_TMP="$(mktemp -d)"
mkdir "$AV_TMP/src" && cp "$F/avatar/ares-x.png" "$AV_TMP/src/"
run python3 -I "$MOD/tools/recolor-assets.py" "$MOD/themes/ares.palette" "$PALETTE" "$AV_TMP/src" "$AV_TMP/out"
run cp "$AV_TMP/out/ares-x.png" "$HOME/.face"
rm -rf "$AV_TMP"
# Lock-screen video, one per palette and style, rendered once each. Style is
# per machine: RICE_LOCKSCREEN in local.env, "grid" (default) or "rain".
# Both renderers read ~/.config/rice/palette.
LOCK_STYLE="$(sed -n "s/^[[:space:]]*RICE_LOCKSCREEN[[:space:]]*=[[:space:]]*[\"']\?\([a-z]*\).*/\1/p" "$LOCAL_ENV" 2>/dev/null | tail -1)"
LOCK_STYLE="${LOCK_STYLE:-grid}"
LOCK_VIDEO="$HOME/Videos/lockscreen/$THEME-$LOCK_STYLE-loop.mp4"
if [ ! -f "$LOCK_VIDEO" ] && command -v ffmpeg >/dev/null && [ "$DRY_RUN" != 1 ]; then
    frames="$(mktemp -d)"
    case "$LOCK_STYLE" in
        rain) python3 -I "$MOD/tools/rain.py" frames "$frames" 1920 1200 240; FPS=24 ;;
        *)    python3 "$MOD/tools/grid.py" frames "$frames" 1920 1200 60; FPS=30 ;;
    esac
    mkdir -p "$(dirname "$LOCK_VIDEO")"
    ffmpeg -y -loglevel error -framerate "$FPS" -i "$frames/f%03d.png" -c:v libx264 \
        -pix_fmt yuv420p -crf 16 -preset slow -tune animation "$LOCK_VIDEO"
    rm -rf "$frames"
    log "render  $LOCK_VIDEO"
fi
LL=org.gnome.shell.extensions.live-lockscreen
LL_SCHEMAS="$HOME/.local/share/gnome-shell/extensions/live-lockscreen@nick-redwill/schemas"
if [ -d "$LL_SCHEMAS" ]; then
    run gsettings --schemadir "$LL_SCHEMAS" set $LL background-video-path "$LOCK_VIDEO"
    run gsettings --schemadir "$LL_SCHEMAS" set $LL playlist-fade-enabled false
fi
run gsettings set org.gnome.login-screen logo ''

# ── Terminal ───────────────────────────────────────────────────────────────
link_file "$F/kitty/current-theme.conf" "$HOME/.config/kitty/current-theme.conf"
# kitty.conf and btop.conf only exist once the app has been installed/run.
[ -f "$HOME/.config/kitty/kitty.conf" ] && run sed -i 's/^# Catppuccin-Mocha$/# Tokyo Night/' "$HOME/.config/kitty/kitty.conf"
link_file "$F/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
link_file "$F/starship.toml" "$HOME/.config/starship.toml"

if ! command -v starship >/dev/null; then
    run sh -c 'curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"'
fi
if ! grep -q 'starship init bash' "$HOME/.bashrc"; then
    [ "$DRY_RUN" = 1 ] || printf '\ncommand -v starship >/dev/null && eval "$(starship init bash)"\n' >> "$HOME/.bashrc"
    log "append  ~/.bashrc starship init"
fi

# Ptyxis is Ubuntu 26.04's default terminal. Same colors as terminator; the
# palette file is recolored by switch-theme.sh like the rest.
link_file "$F/ptyxis/rice.palette" "$HOME/.local/share/org.gnome.Ptyxis/palettes/rice.palette"
if gsettings list-schemas | grep -qx org.gnome.Ptyxis; then
    PTYXIS_PROFILE="$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")"
    PTYXIS_KEY="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$PTYXIS_PROFILE/"
    run gsettings set "$PTYXIS_KEY" palette 'rice'
    run gsettings set "$PTYXIS_KEY" opacity 0.92
    run gsettings set org.gnome.Ptyxis use-system-font false
    run gsettings set org.gnome.Ptyxis font-name 'JetBrains Mono 11'
fi

# ── TUI apps ───────────────────────────────────────────────────────────────
# tmux.conf is shared with AMR hosts, so the theme lives in its own file.
link_file "$F/tmux/tokyonight.conf" "$HOME/.config/tmux/tokyonight.conf"
link_file "$F/cava/config" "$HOME/.config/cava/config"
link_file "$F/fzf.sh" "$HOME/.config/fzf-tokyonight.sh"
if ! grep -q 'fzf-tokyonight' "$HOME/.bashrc"; then
    [ "$DRY_RUN" = 1 ] || printf '[ -f ~/.config/fzf-tokyonight.sh ] && . ~/.config/fzf-tokyonight.sh\n' >> "$HOME/.bashrc"
    log "append  ~/.bashrc fzf colors"
fi
# btop rewrites btop.conf on exit, so edit keys instead of symlinking.
[ -f "$HOME/.config/btop/btop.conf" ] && run sed -i 's/^theme_background = .*/theme_background = False/' "$HOME/.config/btop/btop.conf"

# ── Bash line editing ──────────────────────────────────────────────────────
link_file "$F/readline/rice.inputrc" "$HOME/.config/readline/rice.inputrc"
grep -q 'rice.inputrc' "$HOME/.inputrc" 2>/dev/null || {
    [ "$DRY_RUN" = 1 ] || printf '\n$include ~/.config/readline/rice.inputrc\n' >> "$HOME/.inputrc"
    log "append  ~/.inputrc rice include"
}

# ble.sh replaces readline for inline suggestions + highlighting. It must be
# sourced near the top of .bashrc and attached last, after starship and fzf.
link_file "$F/blerc" "$HOME/.blerc"
if [ ! -f "$HOME/.local/share/blesh/ble.sh" ]; then
    run sh -c 'curl --http1.1 -fsSL https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz | tar xJ -C /tmp && rm -rf "$HOME/.local/share/blesh" && mv /tmp/ble-nightly "$HOME/.local/share/blesh"'
fi
if ! grep -q 'blesh/ble.sh' "$HOME/.bashrc"; then
    [ "$DRY_RUN" = 1 ] || sed -i '/^esac$/{a\
[ -f ~/.local/share/blesh/ble.sh ] \&\& source ~/.local/share/blesh/ble.sh --noattach
:a;n;ba}' "$HOME/.bashrc"
    log "insert  ~/.bashrc ble.sh source"
fi
if ! grep -q 'ble-attach' "$HOME/.bashrc"; then
    [ "$DRY_RUN" = 1 ] || printf '[[ ! ${BLE_VERSION-} ]] || ble-attach\n' >> "$HOME/.bashrc"
    log "append  ~/.bashrc ble-attach"
fi

# ── Rofi ───────────────────────────────────────────────────────────────────
link_file "$F/rofi/config.rasi" "$HOME/.config/rofi/config.rasi"
link_file "$F/rofi/rice.rasi" "$HOME/.config/rofi/rice.rasi"
link_file "$F/rofi/scripts" "$HOME/.config/rofi/scripts"

# Super+Space, Alt+Space and Super+D are taken by GNOME. The laptop's Copilot
# key sends Shift+Super+F23 (seen as XF86TouchpadOff); external keyboards have
# no Copilot key, so Super+R opens it too.
# -normal-window is a flag only: as an override-redirect window rofi gets no
# keyboard focus under XWayland.
# rofi 2.0 (Ubuntu 26.04) picks its Wayland backend when WAYLAND_DISPLAY is
# set, and that needs layer-shell, which GNOME lacks: it dies on launch.
# Unsetting it keeps rofi on XWayland, where rofi-focus expects it.
MEDIA_KEYS=org.gnome.settings-daemon.plugins.media-keys
add_rofi_key() {
    local path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$1/"
    local key="$MEDIA_KEYS.custom-keybinding:$path"
    run gsettings set "$key" name "$2"
    # Toggle: a second press closes rofi. Without this rofi's pidfile lock just
    # makes the new launch exit, so the key seems dead while a menu is open.
    run gsettings set "$key" command "sh -c 'pkill -x rofi || env -u WAYLAND_DISPLAY rofi -show drun -normal-window'"
    run gsettings set "$key" binding "$3"
    local keys
    keys="$(gsettings get $MEDIA_KEYS custom-keybindings)"
    if ! grep -qF "$path" <<<"$keys"; then
        run gsettings set $MEDIA_KEYS custom-keybindings "$(python3 -c 'import ast,sys; print(ast.literal_eval(sys.argv[1].replace("@as ", "")) + [sys.argv[2]])' "$keys" "$path")"
    fi
}
add_rofi_key rofi 'Rofi launcher' '<Shift><Super>XF86TouchpadOff'
add_rofi_key rofi-super-r 'Rofi launcher (Super+R)' '<Super>r'

# ── Qt apps (Dolphin) ──────────────────────────────────────────────────────
# GNOME does not theme Qt apps; qt5ct feeds them the palette and icon theme.
# kdeglobals is separate: Dolphin's item view reads its colors from there.
link_file "$F/kdeglobals" "$HOME/.config/kdeglobals"
link_file "$F/qt5ct/colors/rice.conf" "$HOME/.config/qt5ct/colors/rice.conf"
link_file "$F/environment.d/qt-theme.conf" "$HOME/.config/environment.d/qt-theme.conf"
run mkdir -p "$HOME/.config/qt5ct" "$HOME/.local/share/applications"
# qt5ct rewrites its config on save, so it is generated rather than symlinked.
[ "$DRY_RUN" = 1 ] || sed "s#@HOME@#$HOME#g" "$F/qt5ct/qt5ct.conf" > "$HOME/.config/qt5ct/qt5ct.conf"
# environment.d only applies at next login; the launcher override covers Dolphin now.
DOLPHIN=/usr/share/applications/org.kde.dolphin.desktop
if [ -f "$DOLPHIN" ] && [ "$DRY_RUN" != 1 ]; then
    sed 's|^Exec=dolphin|Exec=env QT_QPA_PLATFORMTHEME=qt5ct dolphin|' \
        "$DOLPHIN" > "$HOME/.local/share/applications/org.kde.dolphin.desktop"
fi

# ── VS Code ────────────────────────────────────────────────────────────────
if code --list-extensions 2>/dev/null | grep -qix enkia.tokyo-night; then
    log "ok      code enkia.tokyo-night"
else
    run code --install-extension enkia.tokyo-night
fi

# ── Claude Code ────────────────────────────────────────────────────────────
# settings.json "theme" lives in the claude-config repo; set it there.
link_file "$F/claude/rice.json" "$HOME/.claude/themes/rice.json"

# ── Per-theme settings ─────────────────────────────────────────────────────
# GTK/shell theme, wallpaper, btop, VS Code, taskbar border come from the
# current palette's @settings; switch-theme.sh owns that logic.
run "$MOD/switch-theme.sh" "$THEME"
