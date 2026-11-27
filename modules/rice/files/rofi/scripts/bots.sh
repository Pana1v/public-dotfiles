#!/usr/bin/env bash
# Rofi script mode: pick a fleet host, then SSH in, start a tmuxinator project
# on it, or open Foxglove on it. Hosts come from the fleet list the conky
# FleetStatus widget pings (label<TAB>address), so there is one list to edit.
# Rows carry "<step>:<host>[:<project>]" in ROFI_INFO.

# Same lookup order as conky's ping_hosts.py: per-machine list wins.
HOSTS_FILES=(
    "$HOME/.config/dotfiles/fleet-hosts.tsv"
    "$HOME/.config/dotfiles/private/conky/fleet-hosts.tsv"
)
TMUXINATOR_DIRS=("$HOME/.config/tmuxinator" "$HOME/.tmuxinator")
SSH_TIMEOUT_SECONDS=3

# foxglove_bridge's default websocket port.
# shortcut: one port for every bot, make it a third fleet column when bots differ.
FOXGLOVE_PORT=8765

# "label<ws>address" rows on stdin, comments and blanks dropped, as "label<TAB>address".
parse_hosts() {
    awk '!NF || $1 ~ /^#/ { next }
         { label = $1; sub(/^[^ \t]+[ \t]+/, ""); sub(/[ \t]+$/, "")
           if ($0 != "" && $0 != label) print label "\t" $0 }'
}

hosts() {
    local f
    for f in "${HOSTS_FILES[@]}"; do
        [ -f "$f" ] || continue
        parse_hosts <"$f"
        return
    done
}

# address <label>
address() { hosts | awk -F'\t' -v h="$1" '$1 == h { print $2; exit }'; }

# ~/.ssh/config knows the label (user, key, jump host) when ssh -G resolves it
# to something else; otherwise fall back to the raw address.
ssh_target() {
    local resolved
    resolved="$(ssh -G "$1" 2>/dev/null | awk '$1 == "hostname" { print $2 }')"
    if [ "$resolved" != "$1" ]; then
        printf '%s' "$1"
        return
    fi
    address "$1"
}

# Local project files win; a bot-only setup is read off the bot instead.
projects() {
    local d names
    for d in "${TMUXINATOR_DIRS[@]}"; do
        [ -d "$d" ] || continue
        names="$(find "$d" -maxdepth 1 -name '*.yml' -printf '%f\n' | sed 's/\.yml$//')"
        [ -n "$names" ] && { printf '%s\n' "$names"; return; }
    done
    ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT_SECONDS" "$(ssh_target "$1")" \
        'tmuxinator list -n' 2>/dev/null | grep -v '^tmuxinator projects'
}

# row <text> <icon> <info>
row() { printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' "$1" "$2" "$3"; }

list_hosts() {
    printf '\0prompt\x1fBOTS\n'
    printf '\0no-custom\x1ftrue\n'
    local label addr
    while IFS=$'\t' read -r label addr; do
        row "$label  $addr" network-server-symbolic "host:$label"
    done < <(hosts)
}

list_actions() {
    printf '\0no-custom\x1ftrue\n'
    printf '\0message\x1f%s\n' "$1"
    row "SSH"        utilities-terminal-symbolic "ssh:$1"
    row "Tmuxinator" view-grid-symbolic          "tmx:$1"
    row "Foxglove"   foxglove-studio          "fox:$1"
    row "Back"       go-previous-symbolic        back
}

list_projects() {
    printf '\0no-custom\x1ftrue\n'
    printf '\0message\x1f%s\n' "$1"
    local p
    while read -r p; do
        row "$p" view-grid-symbolic "run:$1:$p"
    done < <(projects "$1")
    row "Back" go-previous-symbolic "host:$1"
}

# Detached so the window outlives rofi, which exits once this script returns.
detach() { setsid -f "$@" >/dev/null 2>&1; }

# terminator runs a command with -x, same as rofi's run-shell-command.
open_term() { detach terminator -x "$@"; }

selftest() {
    local got
    got="$(printf '# c\n\np1\t10.0.0.1\n  \nbad\nw  host.local  \n' | parse_hosts)"
    [ "$got" = $'p1\t10.0.0.1\nw\thost.local' ] || { echo "parse_hosts: $got"; exit 1; }
    echo ok
}

[ -n "${SELFTEST:-}" ] && { selftest; exit; }

IFS=: read -r step host project <<<"${ROFI_INFO:-}"
case "$step" in
    ""|back) list_hosts ;;
    host)    list_actions "$host" ;;
    ssh)     open_term ssh "$(ssh_target "$host")" ;;
    tmx)     list_projects "$host" ;;
    run)     open_term ssh -t "$(ssh_target "$host")" tmuxinator start "$project" ;;
    fox)     detach foxglove-studio "foxglove://open?ds=foxglove-websocket&ds.url=ws://$(address "$host"):$FOXGLOVE_PORT" ;;
esac
