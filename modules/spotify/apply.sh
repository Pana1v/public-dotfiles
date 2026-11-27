#!/usr/bin/env bash
# Spotify in the rice palette through Spicetify: a "Rice" theme whose
# color.ini is generated from the active palette. switch-theme.sh re-runs
# this, so Spotify follows a palette change on its next start.
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/spotify"
APP=com.spotify.Client

# Spicetify patches Spotify's own files. A system flatpak is root-owned; a
# user one lives in ~/.local/share/flatpak, writable without sudo, and
# current/active stays the same path across updates.
SPOTIFY="$HOME/.local/share/flatpak/app/$APP/current/active/files/extra/share/spotify"
PREFS="$HOME/.var/app/$APP/config/spotify/prefs"

# Pinned: a release at least two weeks old, fetched as a tarball rather than
# piping the install script (which also prompts for the Marketplace).
SPICETIFY_VERSION=2.46.4
SPICETIFY_DIR="$HOME/.spicetify"
SPICETIFY="$SPICETIFY_DIR/spicetify"
THEME="$HOME/.config/spicetify/Themes/Rice"

if flatpak info --user "$APP" >/dev/null 2>&1; then
    log "ok      $APP (user flatpak)"
else
    run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    run flatpak install --user -y --noninteractive flathub "$APP"
    log "install $APP (user flatpak)"
fi
if flatpak info --system "$APP" >/dev/null 2>&1; then
    warn "a system $APP is still installed and stays stock: sudo flatpak uninstall --system -y $APP"
fi

if [ "$("$SPICETIFY" -v 2>/dev/null)" = "$SPICETIFY_VERSION" ]; then
    log "ok      spicetify $SPICETIFY_VERSION"
else
    url="https://github.com/spicetify/cli/releases/download/v$SPICETIFY_VERSION/spicetify-$SPICETIFY_VERSION-linux-amd64.tar.gz"
    tarball="$(mktemp)"
    run curl -fsSL -o "$tarball" "$url"
    run mkdir -p "$SPICETIFY_DIR"
    run tar -xzf "$tarball" -C "$SPICETIFY_DIR"
    rm -f "$tarball"
    log "install spicetify $SPICETIFY_VERSION"
fi

# color.ini: every key Spicetify themes read, from palette roles. Hex without '#'.
PALETTE="$(active_palette)"
role() { sed -n "s/^$1[[:space:]]\+#//p" "$PALETTE"; }
link_file "$MOD/files/user.css" "$THEME/user.css"
if [ "$DRY_RUN" = 1 ]; then
    log "[dry] write $THEME/color.ini"
else
    cat > "$THEME/color.ini" <<EOF
; Generated from the active rice palette by the spotify module. Rewritten on
; every apply: change the palette, not this file.
[Rice]
text               = $(role fg)
subtext            = $(role dim2)
main               = $(role bg)
main-elevated      = $(role bg3)
highlight          = $(role surface)
highlight-elevated = $(role select)
sidebar            = $(role bg2)
player             = $(role bg2)
card               = $(role card)
shadow             = $(role black)
selected-row       = $(role fg2)
button             = $(role accent)
button-active      = $(role cyan)
button-disabled    = $(role bright_black)
tab-active         = $(role surface)
notification       = $(role select)
notification-error = $(role red)
misc               = $(role dim)
EOF
    log "write   $THEME/color.ini"
fi

# Spotify only reads the patch at start. -n: never launch it from here.
if pgrep -x spotify >/dev/null; then
    warn "Spotify is running: close it, then DOTFILES=$DOTFILES bash $MOD/apply.sh"
    exit 0
fi
[ -d "$SPOTIFY" ] || { warn "no Spotify at $SPOTIFY: theme written, not applied"; exit 0; }
run "$SPICETIFY" config spotify_path "$SPOTIFY" prefs_path "$PREFS" \
    current_theme Rice color_scheme Rice inject_css 1 replace_colors 1
# First run backs up stock xpui (~/.local/state/spicetify/Backup). If that
# fails (backup exists, or stale after a Spotify update), restore and redo.
if ! run "$SPICETIFY" -q -n backup apply; then
    run "$SPICETIFY" -q -n restore backup apply
fi
log "rice    Spotify"
