#!/usr/bin/env bash
# Rofi script mode: shortcut cheatsheet for pop-shell and window switching.
# Bindings are read live from gsettings, so rebinding updates the sheet.
# Picking a row just closes rofi.
[ -n "${ROFI_INFO:-}" ] && exit 0

POP=org.gnome.shell.extensions.pop-shell
POP_SCHEMAS="$HOME/.local/share/gnome-shell/extensions/pop-shell@system76.com/schemas"
WM=org.gnome.desktop.wm.keybindings
ROFI_KEY="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/rofi/"
KEY_WIDTH=28

# ['<Super>Left', '<Super>KP_Left', '<Super>h'] -> Super+Left / Super+h
pretty() {
    local raw="${1#@as }" k out=()
    raw="${raw//[\[\]\']/}"
    IFS=',' read -ra keys <<<"$raw"
    for k in "${keys[@]}"; do
        k="${k# }"
        # Keypad copies of the arrows add noise, not information.
        [[ -z "$k" || "$k" == *KP_* ]] && continue
        k="${k//<Super>/Super+}"
        k="${k//<Primary>/Ctrl+}"
        k="${k//<Control>/Ctrl+}"
        k="${k//<Shift>/Shift+}"
        k="${k//<Alt>/Alt+}"
        k="${k//Above_Tab/\`}"
        k="${k//Return/Enter}"
        k="${k//slash//}"
        k="${k//comma/,}"
        out+=("$k")
    done
    local joined
    printf -v joined '%s / ' "${out[@]:0:2}"
    printf '%s' "${joined% / }"
}

header() {
    printf '<span font="Orbitron Bold 8" alpha="55%%">%s</span>\0nonselectable\x1ftrue\n' "$1"
}

# bind <schema> <key> <description>
bind() {
    local schema="$1" key="$2" desc="$3" keys pad
    if [ "$schema" = "$POP" ]; then
        keys="$(gsettings --schemadir "$POP_SCHEMAS" get "$schema" "$key" 2>/dev/null)"
    else
        keys="$(gsettings get "$schema" "$key" 2>/dev/null)"
    fi
    keys="$(pretty "$keys")"
    [ -z "$keys" ] && return

    # Pad by characters, not bytes, so the descriptions line up.
    pad=$((KEY_WIDTH - ${#keys}))
    ((pad < 2)) && pad=2
    printf '<b>%s</b>%*s<span alpha="60%%">%s</span>\0meta\x1f%s\n' "$keys" "$pad" "" "$desc" "$key"
}

printf '\0markup-rows\x1ftrue\n'
printf '\0no-custom\x1ftrue\n'

header "SWITCH"
bind "$WM"  switch-windows          "Switch windows"
bind "$WM"  switch-applications     "Switch apps"
bind "$WM"  switch-group            "Cycle windows of this app"
bind "$ROFI_KEY" binding            "Rofi"
bind "$POP" activate-launcher       "Pop launcher"

header "FOCUS"
bind "$POP" focus-left              "Focus left / prev stack tab"
bind "$POP" focus-right             "Focus right / next stack tab"
bind "$POP" focus-up                "Focus up"
bind "$POP" focus-down              "Focus down"

header "TILING"
bind "$POP" toggle-tiling           "Toggle tiling"
bind "$POP" toggle-floating         "Toggle floating"
bind "$POP" toggle-stacking-global  "Toggle stacking"
bind "$POP" tile-orientation        "Flip split orientation"
bind "$POP" tile-enter              "Enter tile mode"

header "TILE MODE"
bind "$POP" tile-move-left          "Move (any arrow)"
bind "$POP" tile-swap-left          "Swap (any arrow)"
bind "$POP" tile-resize-left        "Resize (any arrow)"
bind "$POP" toggle-stacking         "Stack with neighbour"
bind "$POP" tile-accept             "Apply"
bind "$POP" tile-reject             "Cancel"

header "WORKSPACES"
bind "$WM"  switch-to-workspace-left  "Workspace left"
bind "$WM"  switch-to-workspace-right "Workspace right"
bind "$WM"  move-to-workspace-left    "Move window left"
bind "$WM"  move-to-workspace-right   "Move window right"

header "WINDOW"
bind "$WM"  toggle-maximized        "Maximize"
bind "$WM"  minimize                "Minimize"
bind "$WM"  close                   "Close"
