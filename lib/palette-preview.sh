#!/usr/bin/env bash
# Colour swatches of one rice palette, for bootstrap.sh's theme picker.
#   palette-preview.sh <theme name>
f="$(cd "$(dirname "$0")/.." && pwd)/modules/rice/themes/$1.palette"
[ -f "$f" ] || exit 0
sed -n '1s/^# role[[:space:]]*hex[[:space:]]*//p' "$f"
echo
while read -r role hex _; do
    case "$role" in ''|\#*|@*) continue ;; esac
    h="${hex#\#}"
    printf '\033[48;2;%d;%d;%dm        \033[0m  %-14s %s\n' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}" "$role" "$hex"
done < "$f"
