# shellcheck shell=bash
# Shared helpers for bootstrap.sh and modules/*/apply.sh. Source, don't execute.

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DRY_RUN="${DRY_RUN:-0}"
TS="${TS:-$(date +%Y%m%d-%H%M%S)}"

# Private layer: Pana1v/dotfiles-private, a git submodule at private/. A public
# clone has an empty private/, and every module falls back to its public
# example. ~/.config/dotfiles/private points here so runtime scripts (conky,
# terminator plugins, bashrc) find it without knowing where the repo lives.
PRIVATE="$DOTFILES/private"
has_private() { [ -f "$PRIVATE/private.env" ]; }

# Path of private/<rel> when it exists, else the public fallback $2.
private_or() {
    if [ -e "$PRIVATE/$1" ]; then printf '%s' "$PRIVATE/$1"; else printf '%s' "$2"; fi
}

# Per-machine choices (preset, theme, widgets), never in the repo.
LOCAL_ENV="$HOME/.config/dotfiles/local.env"

# One setting, first hit wins: environment, local.env, private/private.env.
conf_get() {
    local key="$1" f v
    if [ -n "${!key:-}" ]; then printf '%s' "${!key}"; return 0; fi
    for f in "$LOCAL_ENV" "$PRIVATE/private.env"; do
        [ -f "$f" ] || continue
        v="$(sed -n "s/^[[:space:]]*\(export[[:space:]]\+\)\{0,1\}$key=//p" "$f" | tail -1)"
        [ -n "$v" ] || continue
        v="${v%"${v##*[![:space:]]}"}"
        v="${v#[\"\']}"; v="${v%[\"\']}"
        printf '%s' "$v"
        return 0
    done
}

# Write KEY="value" into local.env, replacing an existing KEY line.
local_env_set() {
    local key="$1" val="$2"
    if [ "$DRY_RUN" = 1 ]; then
        log "[dry] $key=\"$val\" in $LOCAL_ENV"
        return 0
    fi
    mkdir -p "$(dirname "$LOCAL_ENV")"
    [ -f "$LOCAL_ENV" ] || printf '# Per-machine choices for the dotfiles (not in the repo).\n' > "$LOCAL_ENV"
    if grep -qE "^[[:space:]]*$key=" "$LOCAL_ENV"; then
        sed -i -E "s|^[[:space:]]*$key=.*|$key=\"$val\"|" "$LOCAL_ENV"
    else
        printf '%s="%s"\n' "$key" "$val" >> "$LOCAL_ENV"
    fi
    log "set     $key=\"$val\" in ${LOCAL_ENV/#$HOME/~}"
}

log()  { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m! %s\033[0m\n' "$*"; }

# Execute, or just print when DRY_RUN=1.
run() {
    if [ "$DRY_RUN" = 1 ]; then
        log "[dry] $*"
        return 0
    fi
    "$@"
}

# Symlink $1 (repo file) to $2 (target), so edits land in the repo.
# An existing non-matching target is moved aside to <target>.bak.<ts>.
link_file() {
    local src="$1" dst="$2"

    if [ "$(readlink "$dst" 2>/dev/null)" = "$src" ]; then
        log "ok      $dst"
        return 0
    fi

    run mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        run mv "$dst" "$dst.bak.$TS"
        log "backup  $dst.bak.$TS"
    fi
    run ln -s "$src" "$dst"
    log "link    $dst"
}

# Copy a directory tree into place. Used where a symlink would break things
# (the target lives inside another git repo, or a program rewrites the files).
copy_tree() {
    local src="$1" dst="$2"
    shift 2
    run mkdir -p "$dst"
    run rsync -a "$@" "$src/" "$dst/"
    log "copy    $dst"
}

# Read a package list: one name per line, '#' comments allowed.
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$'
}

is_zorin() { [ "$(. /etc/os-release && echo "$ID")" = zorin ]; }

# Name of a Zorin-only piece on this distro: itself on Zorin, otherwise its
# replacement from zorin-deps.txt ("-" when dropped). Unlisted names pass through.
distro_name() {
    is_zorin && { echo "$2"; return 0; }
    read_list "$DOTFILES/zorin-deps.txt" |
        awk -v k="$1" -v n="$2" '$1 == k && $2 == n { print $3; f = 1; exit } END { if (!f) print n }'
}

# sed script that turns a Zorin dconf dump into this distro's: theme names
# swapped, extension settings dirs renamed or dropped, zorin-* keys removed.
# Empty on Zorin.
distro_dconf_sed() {
    is_zorin && return 0
    local kind from to
    while read -r kind from to; do
        case "$kind" in
            theme) printf "s/'%s'/'%s'/g\n" "$from" "$to" ;;
            dconf)
                if [ "$to" = - ]; then
                    printf '/^\\[extensions\\/%s[]/]/,/^$/d\n' "$from"
                else
                    printf 's#^\\[extensions/%s\\([]/]\\)#[extensions/%s\\1#\n' "$from" "$to"
                fi ;;
        esac
    done < <(read_list "$DOTFILES/zorin-deps.txt")
    echo '/^zorin-/d'
}

# One install unit per line for snap ("name [--classic]"), one per word otherwise.
# Repeats are dropped, since bootstrap.sh merges several modules' lists.
pkg_items() {
    if [ "$1" = snap ]; then
        read_list "$2"
    else
        read_list "$2" | tr -s ' \t' '\n' | grep -v '^$'
    fi | awk '!seen[$0]++'
}

# True when the item was ticked in bootstrap.sh's picker. With no picker
# (PKG_PICK_FILE empty, e.g. --all-packages or a module run alone) all items pass.
pkg_picked() {
    [ -z "${PKG_PICK_FILE:-}" ] && return 0
    grep -qxF -- "$1 $2" "$PKG_PICK_FILE"
}

# bootstrap.sh installs every module's packages in one step up front and then
# sets PKGS_INSTALLED=1, which turns these helpers into no-ops for the modules.
apt_install() {
    [ "${PKGS_INSTALLED:-0}" = 1 ] && return 0
    local pkgs=() p
    while IFS= read -r p; do
        pkg_picked apt "$p" && pkgs+=("$p")
    done < <(pkg_items apt "$1")
    [ "${#pkgs[@]}" -eq 0 ] && return 0
    run sudo apt-get install -y "${pkgs[@]}"
}

snap_install() {
    [ "${PKGS_INSTALLED:-0}" = 1 ] && return 0
    local line
    while IFS= read -r line; do
        pkg_picked snap "$line" || continue
        # shellcheck disable=SC2086  # line holds "name [--classic]"
        run sudo snap install $line
    done < <(pkg_items snap "$1")
}

flatpak_install() {
    [ "${PKGS_INSTALLED:-0}" = 1 ] && return 0
    local apps=() a
    while IFS= read -r a; do
        pkg_picked flatpak "$a" && apps+=("$a")
    done < <(pkg_items flatpak "$1")
    [ "${#apps[@]}" -eq 0 ] && return 0
    command -v flatpak >/dev/null || run sudo apt-get install -y flatpak
    run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    run flatpak install -y --noninteractive flathub "${apps[@]}"
}

# Run slow, independent steps at once (installers, downloads):
#   spawn <name> <cmd...>   start one in the background, output to a temp log
#   spawn_wait              wait for all, print each log in start order,
#                           fail if any of them failed
SPAWN_PIDS=() SPAWN_NAMES=() SPAWN_LOGS=()
spawn() {
    local name="$1" out
    shift
    out="$(mktemp)"
    "$@" > "$out" 2>&1 &
    SPAWN_PIDS+=("$!") SPAWN_NAMES+=("$name") SPAWN_LOGS+=("$out")
}
spawn_wait() {
    local i rc=0
    for i in "${!SPAWN_PIDS[@]}"; do
        if wait "${SPAWN_PIDS[$i]}"; then
            log "done    ${SPAWN_NAMES[$i]}"
        else
            rc=1
            warn "failed  ${SPAWN_NAMES[$i]}"
        fi
        cat "${SPAWN_LOGS[$i]}"
        rm -f "${SPAWN_LOGS[$i]}"
    done
    SPAWN_PIDS=() SPAWN_NAMES=() SPAWN_LOGS=()
    return "$rc"
}

# Palette file in use: the runtime copy switch-theme.sh writes, else the saved
# RICE_THEME, else whatever the repo files hold (current-theme).
active_palette() {
    local rice="$DOTFILES/modules/rice" theme
    if [ -f "$HOME/.config/rice/palette" ]; then
        printf '%s' "$HOME/.config/rice/palette"
        return 0
    fi
    theme="$(conf_get RICE_THEME)"
    printf '%s' "$rice/themes/${theme:-$(cat "$rice/current-theme")}.palette"
}

# The "Rice" VS Code / Cursor theme, generated from the active palette.
#   rice_vscode_theme <cli> <extensions dir>     e.g. code ~/.vscode/extensions
# First run packages it as a .vsix and installs it with the editor's CLI, so
# the editor registers it. Later runs (and switch-theme.sh) rewrite the
# installed copy in place; reload the editor window to see a new palette.
RICE_VSCODE_THEME="$HOME/.local/share/rice/vscode-rice"
rice_vscode_theme() {
    local cli="$1" installed="$2/local.rice-0.1.0" vsix
    if [ "$DRY_RUN" = 1 ]; then
        log "[dry] generate Rice editor theme for $cli"
        return 0
    fi
    vsix="$(mktemp --suffix=.vsix)"
    python3 -I "$DOTFILES/modules/rice/tools/vscode-theme.py" "$(active_palette)" "$RICE_VSCODE_THEME" "$vsix"
    # An older setup symlinked the theme here; the editor ignores unregistered links.
    [ -L "$installed" ] && rm -f "$installed"
    if [ -d "$installed" ] && "$cli" --list-extensions 2>/dev/null | grep -qx local.rice; then
        rsync -a --delete "$RICE_VSCODE_THEME/" "$installed/"
        log "update  $cli Rice theme"
    elif command -v "$cli" >/dev/null; then
        "$cli" --install-extension "$vsix" --force >/dev/null 2>&1 &&
            log "install $cli Rice theme" || warn "$cli could not install the Rice theme"
    else
        warn "$cli not installed: Rice theme skipped"
    fi
    rm -f "$vsix"
}
