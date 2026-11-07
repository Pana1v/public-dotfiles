#!/usr/bin/env bash
# Rofi script mode backed by qalc. Script modes can't evaluate while you type,
# so the flow is: type an expression, Enter shows the answer, Enter on the
# answer copies it. Units and conversions work too ("5 ft to m", "0x1f to dec").

printf '\0prompt\x1fCalc\n'
printf '\0markup-rows\x1ffalse\n'

if ! command -v qalc >/dev/null; then
    printf '\0message\x1fqalc missing: sudo apt install qalc xclip\n'
    exit 0
fi

if [ -n "${ROFI_INFO:-}" ]; then
    # Picked a result row: copy the bare value and close rofi.
    printf '%s' "$ROFI_INFO" | xclip -selection clipboard
    exit 0
fi

if [ -z "${1:-}" ]; then
    printf '\0message\x1fType an expression, Enter to solve\n'
    exit 0
fi

# -t drops the "expr =" echo so only the answer comes back.
answer="$(qalc -t -- "$1" 2>&1 | tail -n1)"
printf '\0message\x1f%s\n' "$1"
printf '%s\0icon\x1faccessories-calculator\x1finfo\x1f%s\n' "$answer" "$answer"
