#!/usr/bin/env bash
# One-off dual-boot repair plus the Ares GRUB theme. Run with sudo.
#
#   1. Root partition (nvme0n1p5) is typed "EFI System". The HP firmware then
#      sees two ESPs, can't read the ext4 one, and drops into its recovery path.
#      Retype it to "Linux filesystem". Only the GPT type GUID changes; no data
#      is touched.
#   2. The only firmware entry is "Windows Boot Manager" pointing at Ubuntu's
#      shim. When the firmware or a Windows update "repairs" it, fbx64.efi has
#      to rebuild entries on the next boot (the recovery you see). Add a real
#      "The Grid" entry and put it first. The old entry stays as a fallback.
#   3. GRUB menu was hidden with a 0s timeout and os-prober off, so Windows was
#      only reachable through the firmware. Show the menu for 5s, add Windows,
#      install the Ares theme.
#
# Backups land in /root/boot-backup-<timestamp>/.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

DISK=/dev/nvme0n1
ROOT_PART=5
ESP_PART=1
HERE="$(cd "$(dirname "$0")" && pwd)"
BK="/root/boot-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
sgdisk --backup="$BK/gpt.bin" "$DISK"
efibootmgr -v > "$BK/efibootmgr.txt"
cp /etc/default/grub "$BK/grub.default"
echo "backups in $BK"

# ---- 1. partition type ------------------------------------------------------
# Sanity: p5 must be the ext4 root we are running from.
[ "$(findmnt -no SOURCE /)" = "${DISK}p${ROOT_PART}" ] || { echo "p$ROOT_PART is not / ; stopping" >&2; exit 1; }
sgdisk --typecode="$ROOT_PART:8300" "$DISK"
echo "p$ROOT_PART type -> Linux filesystem"

# ---- 2. firmware entry ------------------------------------------------------
LABEL="The Grid"
if ! efibootmgr | grep -q "^Boot[0-9A-F]\{4\}\*\? $LABEL\s"; then
    efibootmgr -q -c -d "$DISK" -p "$ESP_PART" -L "$LABEL" -l '\EFI\ubuntu\shimx64.efi'
fi
NEW="$(efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\? $LABEL\s.*/\1/p" | head -1)"
REST="$(efibootmgr | sed -n 's/^BootOrder: //p' | tr ',' '\n' | grep -v "^$NEW$" | paste -sd,)"
efibootmgr -q -o "$NEW${REST:+,$REST}"
efibootmgr -t 3 >/dev/null 2>&1 || true   # firmware menu timeout, harmless if HP ignores it
# fbx64.efi rebuilds entries from this file; it said "Kubuntu". UTF-16LE with BOM
# like the shim package ships it (a shim update may put the old name back).
CSV=/boot/efi/EFI/ubuntu/BOOTX64.CSV
cp "$CSV" "$BK/" 2>/dev/null || true
printf '\xff\xfe' > "$CSV"
printf 'shimx64.efi,%s,,This is the boot entry for %s\n' "$LABEL" "$LABEL" | iconv -t UTF-16LE >> "$CSV"
echo "firmware: $LABEL entry Boot$NEW first"

# ---- 3. GRUB ------------------------------------------------------------------
THEME_DIR=/boot/grub/themes/ares
mkdir -p "$THEME_DIR"
cp "$HERE"/files/grub/ares/* "$THEME_DIR/"

set_grub() {  # set_grub KEY VALUE: replace or append in /etc/default/grub
    if grep -q "^#\?$1=" /etc/default/grub; then
        sed -i "s|^#\?$1=.*|$1=$2|" /etc/default/grub
    else
        echo "$1=$2" >> /etc/default/grub
    fi
}
set_grub GRUB_TIMEOUT_STYLE menu
set_grub GRUB_TIMEOUT 5
set_grub GRUB_DISABLE_OS_PROBER false
# Must stay Ubuntu: grub-install takes its EFI folder (EFI/ubuntu, where the
# firmware entry points) from GRUB_DISTRIBUTOR. The menu name is changed below.
set_grub GRUB_DISTRIBUTOR "'Ubuntu'"
set_grub GRUB_GFXMODE 1920x1080,auto
set_grub GRUB_THEME "\"$THEME_DIR/theme.txt\""
# Windows updates can leave the last choice on Windows; always default to Linux.
set_grub GRUB_DEFAULT 0

# Menu says "The Grid" instead of Ubuntu: wrap 10_linux and rename its entries.
# A grub package update may make 10_linux executable again; then both names show.
cat > /etc/grub.d/10_the_grid <<'GRID'
#!/bin/sh
# Rice: 10_linux with its entries renamed to "The Grid" (see fix-boot-and-grub.sh).
sh /etc/grub.d/10_linux | sed "s/menuentry 'Ubuntu/menuentry 'The Grid/; s/submenu 'Advanced options for Ubuntu/submenu 'Advanced options for The Grid/"
GRID
chmod +x /etc/grub.d/10_the_grid
chmod -x /etc/grub.d/10_linux

update-grub
echo
grep -q "Windows" /boot/grub/grub.cfg && echo "GRUB: Windows entry found" || echo "GRUB: no Windows entry (os-prober found nothing)"
grep -o "menuentry '[^']*'" /boot/grub/grub.cfg | head -5
echo "done. Reboot to check. Restore: sgdisk --load-backup=$BK/gpt.bin $DISK ; cp $BK/grub.default /etc/default/grub ; rm /etc/grub.d/10_the_grid ; chmod +x /etc/grub.d/10_linux ; update-grub"
