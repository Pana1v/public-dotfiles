#!/usr/bin/env bash
# Lets the power menu (power-extras@pan.local) restart straight into Windows.
# Run once with sudo. Safe to run again.
#
#   1. A firmware entry "Windows" on Microsoft's own loader. The existing
#      "Windows Boot Manager" entry points at Ubuntu's shim (see
#      system-rice.sh), so it can't be used to reach Windows. The new entry
#      goes last in BootOrder, so normal boots are unchanged.
#   2. /usr/local/sbin/reboot-to-windows sets BootNext to that entry (one boot
#      only) and restarts. A sudoers rule lets the sudo group run just that
#      script without a password, so the menu item needs no prompt.
#
# Restart to UEFI setup needs none of this: logind allows it for the session.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

DISK=/dev/nvme0n1
ESP_PART=1
LABEL=Windows
LOADER='\EFI\Microsoft\Boot\bootmgfw.efi'
[ -f /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi ] || { echo "no Windows loader on the ESP" >&2; exit 1; }

# Exact label: efibootmgr puts a tab between the label and the device path,
# so "Windows" does not match "Windows Boot Manager".
entry_id() {
    efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\{0,1\} $1	.*/\1/p" | head -1
}

ID="$(entry_id "$LABEL")"
if [ -z "$ID" ]; then
    efibootmgr -q -c -d "$DISK" -p "$ESP_PART" -L "$LABEL" -l "$LOADER"
    ID="$(entry_id "$LABEL")"
    # -c puts the new entry first; move it to the end.
    REST="$(efibootmgr | sed -n 's/^BootOrder: //p' | tr ',' '\n' | grep -v "^$ID$" | paste -sd,)"
    efibootmgr -q -o "${REST:+$REST,}$ID"
    echo "firmware: $LABEL (Boot$ID) added, last in boot order"
else
    echo "firmware: $LABEL (Boot$ID) already there"
fi

cat > /usr/local/sbin/reboot-to-windows <<'EOF'
#!/bin/sh
# Boot Windows once, then back to the normal order. Installed by reboot-targets.sh.
set -e
id="$(efibootmgr | sed -n 's/^Boot\([0-9A-F]\{4\}\)\*\{0,1\} Windows	.*/\1/p' | head -1)"
[ -n "$id" ] || { echo "no Windows firmware entry; run reboot-targets.sh" >&2; exit 1; }
efibootmgr -q -n "$id"
systemctl reboot
EOF
chmod 755 /usr/local/sbin/reboot-to-windows

RULE=/etc/sudoers.d/reboot-to-windows
echo '%sudo ALL=(root) NOPASSWD: /usr/local/sbin/reboot-to-windows' > "$RULE.tmp"
chmod 440 "$RULE.tmp"
visudo -cqf "$RULE.tmp"
mv "$RULE.tmp" "$RULE"
echo "installed /usr/local/sbin/reboot-to-windows and $RULE"
echo "undo: efibootmgr -b $ID -B; rm /usr/local/sbin/reboot-to-windows $RULE"
