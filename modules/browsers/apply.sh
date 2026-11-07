#!/usr/bin/env bash
# Rice every installed browser with the active palette: Chromium family
# (Chrome, Brave, Chromium, Edge, Vivaldi) and Firefox family (Firefox,
# LibreWolf, Zen), as deb, flatpak or snap, every profile. switch-theme.sh
# re-runs this, so browsers follow a palette change on their next start.
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/browsers"
RICE="$DOTFILES/modules/rice"
PY="$MOD/files/rice_browsers.py"

apt_install "$MOD/packages.apt"

# Active palette: the runtime copy switch-theme.sh writes, else the saved or
# current theme.
PALETTE="$HOME/.config/rice/palette"
if [ ! -f "$PALETTE" ]; then
    THEME="$(conf_get RICE_THEME)"
    PALETTE="$RICE/themes/${THEME:-$(cat "$RICE/current-theme")}.palette"
fi
log "palette $(sed -n '1s/^# role[[:space:]]*hex[[:space:]]*//p' "$PALETTE" | cut -d. -f1)"

# Background: BROWSER_BG in local.env, "rain" (default, animated digital rain
# in the palette colours) or "static" (the palette wallpaper). The start page
# draws the rain live (startpage/rain.js). Native new tab pages cannot run
# scripts, so they get a seamless animated WebP loop rendered by the lock
# screen's rain.py, cached per palette in ~/.cache/rice.
BG_MODE="$(conf_get BROWSER_BG)"
BG_MODE="${BG_MODE:-rain}"
export RICE_ASCII=none RICE_NEWTAB_IMAGE=""
if [ "$BG_MODE" = rain ]; then
    RICE_ASCII=rain
    LOOP="$HOME/.cache/rice/newtab-rain-$(sha1sum "$PALETTE" | cut -c1-10).webp"
    if [ -s "$LOOP" ]; then
        log "ok      new tab rain loop"
        RICE_NEWTAB_IMAGE="$LOOP"
    elif ! python3 -c 'import PIL' 2>/dev/null ||
        [[ "$(ffmpeg -hide_banner -encoders 2>/dev/null)" != *libwebp_anim* ]]; then
        warn "new tab rain needs python3-pil and ffmpeg with libwebp: using the static wallpaper"
    elif [ "$DRY_RUN" = 1 ]; then
        log "[dry] render new tab rain loop to $LOOP"
    else
        frames="$(mktemp -d)"
        mkdir -p "$(dirname "$LOOP")"
        rm -f "$HOME"/.cache/rice/newtab-rain-*.webp
        if RICE_PALETTE="$PALETTE" python3 -I "$RICE/tools/rain.py" frames "$frames" 1280 800 120 &&
            ffmpeg -loglevel error -y -framerate 20 -i "$frames/f%03d.png" -c:v libwebp_anim \
                -lossless 0 -q:v 50 -compression_level 4 -loop 0 "$LOOP"; then
            log "render  new tab rain loop ($(du -h "$LOOP" | cut -f1))"
            RICE_NEWTAB_IMAGE="$LOOP"
        else
            warn "rain loop render failed: using the static wallpaper"
        fi
        rm -rf "$frames"
    fi
fi
log "bg      $BG_MODE"

SHARE="$HOME/.local/share/rice"
link_file "$MOD/files/startpage" "$SHARE/startpage"
run python3 -I "$PY" css "$PALETTE" "$SHARE/palette.css"
START_URL="file://$SHARE/startpage/index.html"

# Snaps cannot read hidden folders like ~/.local, so a snap browser gets its
# own copy of the start page inside its snap folder.
snap_start_url() {
    local dir="$HOME/snap/$1/common/rice"
    copy_tree "$MOD/files/startpage" "$dir/startpage" --delete >&2
    # palette.css and the wallpaper it points at (rice-*); drop old wallpapers.
    run find "$dir" -maxdepth 1 -name 'rice-*' -delete >&2
    run cp "$SHARE/palette.css" "$SHARE"/rice-* "$dir/" >&2
    printf 'file://%s/startpage/index.html' "$dir"
}

# Flatpaks see only what they are granted: read-only access to the start page.
flatpak_grant() {
    flatpak info "$1" >/dev/null 2>&1 || return 0
    if flatpak override --user --show "$1" 2>/dev/null | grep -q '~/.local/share/rice:ro'; then
        log "ok      $1 can read the start page"
    else
        run flatpak override --user --filesystem=~/.local/share/rice:ro "$1"
        log "set     $1 read access to ~/.local/share/rice"
    fi
}

# A running browser rewrites its prefs on exit and would undo the patch.
running() { pgrep -x "$1" >/dev/null; }
RERUN="DOTFILES=$DOTFILES bash $MOD/apply.sh"
found=0

# name | user-data dir | process name | flatpak id or snap:<name>
CHROMIUM=(
    "Chrome|$HOME/.config/google-chrome|chrome|"
    "Chrome (flatpak)|$HOME/.var/app/com.google.Chrome/config/google-chrome|chrome|com.google.Chrome"
    "Brave|$HOME/.config/BraveSoftware/Brave-Browser|brave|"
    "Brave (flatpak)|$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser|brave|com.brave.Browser"
    "Chromium|$HOME/.config/chromium|chromium|"
    "Chromium (snap)|$HOME/snap/chromium/common/chromium|chromium|snap:chromium"
    "Chromium (flatpak)|$HOME/.var/app/org.chromium.Chromium/config/chromium|chromium|org.chromium.Chromium"
    "Edge|$HOME/.config/microsoft-edge|msedge|"
    "Edge (flatpak)|$HOME/.var/app/com.microsoft.Edge/config/microsoft-edge|msedge|com.microsoft.Edge"
    "Vivaldi|$HOME/.config/vivaldi|vivaldi-bin|"
)
for row in "${CHROMIUM[@]}"; do
    IFS='|' read -r name dir proc pkg <<< "$row"
    [ -d "$dir/Default" ] || continue
    found=1
    if running "$proc"; then
        warn "$name is running: close it, then $RERUN"
        continue
    fi
    url="$START_URL"
    case "$pkg" in
        snap:*) url="$(snap_start_url "${pkg#snap:}")" ;;
        ?*)     flatpak_grant "$pkg" ;;
    esac
    run python3 -I "$PY" chromium "$dir" "$PALETTE" "$url"
    log "rice    $name"
done

# name | profiles root (holds profiles.ini) | process name | flatpak id or snap:<name>
FIREFOX=(
    "Firefox|$HOME/.mozilla/firefox|firefox|"
    "Firefox|$HOME/.config/mozilla/firefox|firefox|"
    "Firefox (snap)|$HOME/snap/firefox/common/.mozilla/firefox|firefox|snap:firefox"
    "Firefox (flatpak)|$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox|firefox|org.mozilla.firefox"
    "LibreWolf|$HOME/.librewolf|librewolf|"
    "LibreWolf (flatpak)|$HOME/.var/app/io.gitlab.librewolf-community/.librewolf|librewolf|io.gitlab.librewolf-community"
    "Zen|$HOME/.zen|zen|"
    "Zen (flatpak)|$HOME/.var/app/app.zen_browser.zen/.zen|zen|app.zen_browser.zen"
)
for row in "${FIREFOX[@]}"; do
    IFS='|' read -r name root proc pkg <<< "$row"
    [ -f "$root/profiles.ini" ] || continue
    found=1
    if running "$proc"; then
        warn "$name is running: close it, then $RERUN"
        continue
    fi
    url="$START_URL"
    case "$pkg" in
        snap:*) url="$(snap_start_url "${pkg#snap:}")" ;;
        ?*)     flatpak_grant "$pkg" ;;
    esac
    # Path= lines of profiles.ini, relative to the root unless absolute.
    while IFS= read -r rel; do
        [[ "$rel" = /* ]] && prof="$rel" || prof="$root/$rel"
        [ -d "$prof" ] || continue
        run python3 -I "$PY" firefox "$prof" "$PALETTE" "$url"
        log "rice    $name ($(basename "$prof"))"
    done < <(sed -n 's/^Path=//p' "$root/profiles.ini")
done

[ "$found" = 1 ] || log "skip    no browser profiles yet (start each browser once, then re-run)"
