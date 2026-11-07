#!/usr/bin/env bash
# System side of the rice. Run with sudo. Safe to run again.
#
#   1. Boot error "Failed to open \EFI\ubuntu\<garbage>": the only firmware
#      entry, "Windows Boot Manager", points at shim but still carries the
#      Windows BCD blob ("WINDOWS....BCDOBJECT={...}") as load options. Shim
#      reads load options as the path of the next loader, fails on the junk,
#      then falls back to grubx64.efi. Recreate that entry without the blob and
#      put a clean "The Grid" entry first.
#   2. Plymouth: the "Ares Grid" splash (moving grid) instead of the vendor logo.
#      Steps 2-4 recolour their assets for the machine's palette (RICE_THEME).
#   3. GDM: no Ubuntu logo, grid background, lock-screen styling, X avatar.
#   4. GRUB: new grid background (no stray L line), menu at the panel's 1920x1200.
#
# Step 1 rewrites firmware boot entries for one specific HP laptop, so it only
# runs with --firmware. Steps 2-4 are safe on any machine.
#
#   sudo ./system-rice.sh              splash, greeter / lock screen, GRUB theme
#   sudo ./system-rice.sh --firmware   also step 1
#
# Backups land in /root/rice-backup-<timestamp>/.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
FIRMWARE=0
[ "${1:-}" = --firmware ] && FIRMWARE=1

HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/files"
USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || id -un)}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
DISK=/dev/nvme0n1
ESP_PART=1
BK="/root/rice-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
echo "backups in $BK"

# The splash, greeter, GRUB and avatar assets are drawn in the Ares palette.
# Recolour a copy for this machine's palette: RICE_THEME in the user's
# local.env, else whatever the repo files hold (current-theme).
THEME="$(sed -n "s/^[[:space:]]*RICE_THEME[[:space:]]*=[[:space:]]*[\"']\?\([A-Za-z0-9_-]*\).*/\1/p" \
    "$USER_HOME/.config/dotfiles/local.env" 2>/dev/null | tail -1)"
THEME="${THEME:-$(cat "$HERE/current-theme")}"
[ -f "$HERE/themes/$THEME.palette" ] || { echo "no palette themes/$THEME.palette" >&2; exit 1; }
ASSETS="$(mktemp -d)"
WORK=""
trap 'rm -rf "$ASSETS" ${WORK:+"$WORK"}' EXIT
mkdir "$ASSETS/src"
cp -r "$F"/grub "$F"/gdm "$F"/plymouth "$F"/avatar "$ASSETS/src/"
python3 -I "$HERE/tools/recolor-assets.py" "$HERE/themes/ares.palette" "$HERE/themes/$THEME.palette" \
    "$ASSETS/src" "$ASSETS/out"
F="$ASSETS/out"
echo "assets: recoloured for the $THEME palette"

# ---- 1. firmware boot entries (--firmware only) -------------------------------
if [ "$FIRMWARE" = 1 ]; then
efibootmgr -v > "$BK/efibootmgr.txt"
LOADER='\EFI\ubuntu\shimx64.efi'

entry_id() {  # entry_id LABEL -> 4-hex id of the first entry with that label
    efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\? $1\s.*/\1/p" | head -1
}

# The Windows entry on shim with the BCD blob is what prints the garbage path.
WBM="$(entry_id 'Windows Boot Manager')"
if [ -n "$WBM" ] && efibootmgr -v | grep "^Boot$WBM" | grep -qi 'shimx64.efi' \
   && efibootmgr -v | grep "^Boot$WBM" | grep -q '57494e444f5753'; then   # "WINDOWS"
    efibootmgr -q -b "$WBM" -B
    efibootmgr -q -c -d "$DISK" -p "$ESP_PART" -L 'Windows Boot Manager' -l "$LOADER"
    echo "firmware: Windows Boot Manager recreated on shim without the BCD load options"
fi

GRID="$(entry_id 'The Grid')"
if [ -z "$GRID" ]; then
    efibootmgr -q -c -d "$DISK" -p "$ESP_PART" -L 'The Grid' -l "$LOADER"
    GRID="$(entry_id 'The Grid')"
fi
REST="$(efibootmgr | sed -n 's/^BootOrder: //p' | tr ',' '\n' | grep -v "^$GRID$" | paste -sd,)"
efibootmgr -q -o "$GRID${REST:+,$REST}"
echo "firmware: The Grid (Boot$GRID) first"
efibootmgr
else
    echo "firmware: skipped (pass --firmware for the HP boot-entry fix)"
fi

# ---- 2. Plymouth ----------------------------------------------------------------
PDIR=/usr/share/plymouth/themes/ares-grid
mkdir -p "$PDIR"
rm -f "$PDIR"/*
cp "$F"/plymouth/ares-grid/* "$PDIR/"
readlink -f /etc/alternatives/default.plymouth > "$BK/plymouth-default.txt" || true
update-alternatives --quiet --install /usr/share/plymouth/themes/default.plymouth \
    default.plymouth "$PDIR/ares-grid.plymouth" 200
update-alternatives --quiet --set default.plymouth "$PDIR/ares-grid.plymouth"
echo "plymouth: ares-grid set, rebuilding initramfs"
update-initramfs -u

# ---- 3. GDM ------------------------------------------------------------------------
# Fonts the greeter needs (it cannot see ~/.local/share/fonts).
mkdir -p /usr/local/share/fonts/rice
cp "$USER_HOME"/.local/share/fonts/Orbitron* /usr/local/share/fonts/rice/ 2>/dev/null || true
fc-cache -f /usr/local/share/fonts/rice >/dev/null

# Theme: the distro GDM theme with rice.css appended and the grid image added.
command -v glib-compile-resources >/dev/null || apt-get install -y libglib2.0-dev-bin
SRC=/usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource
[ -f "$SRC" ] || SRC=/usr/share/gnome-shell/gnome-shell-theme.gresource
WORK="$(mktemp -d)"
for r in $(gresource list "$SRC"); do
    mkdir -p "$WORK/$(dirname "${r#/org/gnome/shell/theme/}")"
    gresource extract "$SRC" "$r" > "$WORK/${r#/org/gnome/shell/theme/}"
done
for css in "$WORK"/gdm.css "$WORK"/*/gnome-shell*.css "$WORK"/gnome-shell*.css; do
    [ -f "$css" ] && cat "$F/gdm/rice.css" >> "$css"
done
cp "$F/gdm/grid.png" "$WORK/rice-grid.png"
{
    echo '<?xml version="1.0" encoding="UTF-8"?><gresources><gresource prefix="/org/gnome/shell/theme">'
    (cd "$WORK" && find . -type f ! -name '*.xml' | sed 's|^\./|  <file>|; s|$|</file>|')
    echo '</gresource></gresources>'
} > "$WORK/rice.gresource.xml"
mkdir -p /usr/share/gnome-shell/theme/Rice
glib-compile-resources --sourcedir="$WORK" \
    --target=/usr/share/gnome-shell/theme/Rice/gnome-shell-theme.gresource "$WORK/rice.gresource.xml"
update-alternatives --quiet --install /usr/share/gnome-shell/gdm-theme.gresource gdm-theme.gresource \
    /usr/share/gnome-shell/theme/Rice/gnome-shell-theme.gresource 20
update-alternatives --quiet --set gdm-theme.gresource /usr/share/gnome-shell/theme/Rice/gnome-shell-theme.gresource
echo "gdm: Rice theme installed"

# No Ubuntu logo on the greeter. Ubuntu's gdm profile reads one compiled file
# built from /usr/share/gdm/dconf (which links /etc/gdm3/greeter.dconf-defaults).
# The greeter also runs grid-live (system-wide copy), so the login screen has
# the same moving grid as the splash before it and the desktop after it.
cat > /usr/share/gdm/dconf/95-rice <<'EOF'
[org/gnome/login-screen]
logo=''

[org/gnome/shell]
enabled-extensions=['grid-live@pan.local']
EOF
EXT=/usr/share/gnome-shell/extensions/grid-live@pan.local
rm -rf "$EXT"
cp -r "$HERE/../gnome-extensions/files/grid-live@pan.local" "$EXT"
chmod -R a+rX "$EXT"
echo "gdm: grid-live enabled on the login screen"
dconf compile /var/lib/gdm3/greeter-dconf-defaults /usr/share/gdm/dconf

# Avatar for the greeter list.
if [ -f "$F/avatar/ares-x.png" ]; then
    cp "$F/avatar/ares-x.png" "/var/lib/AccountsService/icons/$USER_NAME"
    chmod 644 "/var/lib/AccountsService/icons/$USER_NAME"
fi

# ---- 4. GRUB -------------------------------------------------------------------------
# Installs the Ares theme if missing, and shows the menu for 5s so it is seen
# (Ubuntu ships it hidden with a 0s timeout).
{
    mkdir -p /boot/grub/themes/ares
    cp "$F"/grub/ares/* /boot/grub/themes/ares/
    cp /etc/default/grub "$BK/grub.default"
    set_grub() {  # set_grub KEY VALUE: replace or append in /etc/default/grub
        if grep -q "^#\?$1=" /etc/default/grub; then
            sed -i "s|^#\?$1=.*|$1=$2|" /etc/default/grub
        else
            echo "$1=$2" >> /etc/default/grub
        fi
    }
    set_grub GRUB_THEME /boot/grub/themes/ares/theme.txt
    set_grub GRUB_TIMEOUT_STYLE menu
    set_grub GRUB_TIMEOUT 5
    set_grub GRUB_GFXMODE 1920x1200,1920x1080,auto
    # After an entry is picked GRUB drops to its terminal, which is black unless
    # it has a background: give it the same grid frame, and hand that framebuffer
    # to the kernel untouched, so the picture holds until the splash animates it.
    set_grub GRUB_BACKGROUND /boot/grub/themes/ares/background.png
    set_grub GRUB_GFXPAYLOAD_LINUX keep
    update-grub
}

echo
echo "done. Reboot to see the splash and greeter."
echo "undo: update-alternatives --auto default.plymouth; update-alternatives --auto gdm-theme.gresource;"
echo "      cp $BK/grub.default /etc/default/grub && update-grub;"
echo "      rm -r /usr/share/gdm/dconf/95-rice /usr/share/gnome-shell/extensions/grid-live@pan.local; dconf compile /var/lib/gdm3/greeter-dconf-defaults /usr/share/gdm/dconf; update-initramfs -u"
