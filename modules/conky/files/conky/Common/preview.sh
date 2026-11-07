#!/bin/bash
# Render a widget to a PNG without showing it:  preview.sh <Dir/name> <out.png>
#   preview.sh Calendar/calendar /tmp/cal.png
# Uses the widget's own .conf for size and script; needs no X window.
set -euo pipefail
CONKY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
conf="$CONKY_DIR/$1.conf"
w=$(sed -n 's/^\s*minimum_width\s*=\s*\([0-9]*\).*/\1/p' "$conf")
h=$(sed -n 's/^\s*minimum_height\s*=\s*\([0-9]*\).*/\1/p' "$conf")
tmp="$(mktemp --suffix=.conf)"
trap 'rm -f "$tmp"' EXIT
sed -e "s#'~/#'$HOME/#g" \
    -e 's/^\(\s*out_to_x\s*=\s*\)true/\1false/' \
    -e 's/^\(\s*total_run_times\s*=\s*\)[0-9]*/\12/' \
    -e 's/^\(\s*own_window\s*=\s*\)true/\1false/' \
    "$conf" > "$tmp"
printf '\nconky.config.out_to_console = true\nconky.config.update_interval = 0.2\n' >> "$tmp" 2>/dev/null || true
CONKY_PREVIEW="${w}x${h}:$2" timeout 20 conky -c "$tmp" >/dev/null 2>"$tmp.err" || true
grep -E 'error|nil|attempt' "$tmp.err" || true
rm -f "$tmp.err"
[ -f "$2" ] && echo "wrote $2 (${w}x${h})"
