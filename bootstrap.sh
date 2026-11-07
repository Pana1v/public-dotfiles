#!/usr/bin/env bash
# Pick a preset, modules and a colour theme, then apply them to this machine.
#
#   ./bootstrap.sh                 pickers: preset, modules (preset ones ticked), theme
#   ./bootstrap.sh --preset professional --theme tron
#                                  no pickers: that preset's modules, that palette
#   ./bootstrap.sh --only conky,tmux
#   ./bootstrap.sh --all
#   ./bootstrap.sh --list          modules, presets and themes
#   ./bootstrap.sh --setup         ask preset, theme and lock screen again
#   ./bootstrap.sh --lockscreen rain   lock-screen video: grid or rain
#   ./bootstrap.sh --dry-run ...   print actions, change nothing
#   ./bootstrap.sh --all-packages  skip the package picker, install every listed package
#   ./bootstrap.sh --serial ...    one module at a time, output streamed live
#   ./bootstrap.sh --keep-going    a failed module skips only its dependents
#
# Presets (presets/*.env) set PROFILE and CONKY_WIDGETS and list default
# modules. Preset, theme and lock screen are saved to
# ~/.config/dotfiles/local.env, so later runs do not ask again.
#
# The private repo (private/, a git submodule) is checked out when this
# account can read it; otherwise modules use their public examples.
#
# Selected modules pull in their DEPENDS (from module.env) first.
# Before anything installs, the apt/snap/flatpak packages of those modules are
# listed for ticking. Only the ticked ones get installed.
#
# Order of work: sudo once, apt-repos, then every ticked apt package in one go,
# then the modules in parallel while snaps and flatpaks finish downloading.
# A module starts once its DEPENDS are done; modules sharing a LOCKS name
# (module.env) never run at the same time.
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES
# shellcheck source=lib/common.sh
. "$DOTFILES/lib/common.sh"

usage() { sed -n '2,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit "${1:-0}"; }

module_field() {
    # shellcheck disable=SC1090
    ( . "$DOTFILES/modules/$1/module.env"; printf '%s' "${!2:-}" )
}

all_modules() {
    local d
    for d in "$DOTFILES"/modules/*/; do
        basename "$d"
    done
}

list_modules() {
    local m
    for m in $(all_modules); do
        printf '%-18s %s\n' "$m" "$(module_field "$m" DESC)"
    done
}

preset_field() {
    # shellcheck disable=SC1090
    ( . "$DOTFILES/presets/$1.env"; printf '%s' "${!2:-}" )
}

list_presets() {
    local f
    for f in "$DOTFILES"/presets/*.env; do
        f="$(basename "$f" .env)"
        printf '%-14s %s\n' "$f" "$(preset_field "$f" DESC)"
    done
}

list_themes() {
    local f
    for f in "$DOTFILES"/modules/rice/themes/*.palette; do
        printf '%-12s %s\n' "$(basename "$f" .palette)" \
            "$(sed -n '1s/^# role[[:space:]]*hex[[:space:]]*//p' "$f")"
    done
}

ensure_fzf() {
    command -v fzf >/dev/null && return 0
    echo "fzf not found, installing it for the picker" >&2
    sudo apt-get install -y fzf >&2
}

pick_preset() {
    ensure_fzf
    list_presets | fzf --reverse --height=40% --prompt='preset> ' \
        --header='What kind of machine is this? ENTER picks, ESC skips' | awk '{print $1}'
}

pick_theme() {
    ensure_fzf
    list_themes | fzf --reverse --height=80% --prompt='theme> ' \
        --header='Colour theme for the whole desktop. ENTER picks, ESC keeps the current one' \
        --preview "bash '$DOTFILES/lib/palette-preview.sh' {1}" --preview-window=right,55% |
        awk '{print $1}'
}

pick_lockscreen() {
    ensure_fzf
    printf '%s\n' "grid   palette-coloured grid video" "rain   looping digital rain" |
        fzf --reverse --height=30% --prompt='lock screen> ' \
            --header='Lock-screen background. ENTER picks, ESC keeps the current one' | awk '{print $1}'
}

# Check out private/ when this account can read Pana1v/dotfiles-private, and
# point ~/.config/dotfiles/private at it for runtime scripts.
setup_private() {
    if ! has_private && [ -f "$DOTFILES/.gitmodules" ] && [ "$DRY_RUN" != 1 ]; then
        if GIT_TERMINAL_PROMPT=0 git -C "$DOTFILES" submodule update --init private >/dev/null 2>&1; then
            log "private repo checked out"
        else
            warn "private repo not readable from this account: modules use their public examples"
        fi
    fi
    if has_private; then
        link_file "$PRIVATE" "$HOME/.config/dotfiles/private"
        install_leak_hook
    fi
}

# Pre-commit hook: refuse public commits that add a private value.
install_leak_hook() {
    local hook
    hook="$(git -C "$DOTFILES" rev-parse --git-path hooks/pre-commit 2>/dev/null)" || return 0
    [[ "$hook" = /* ]] || hook="$DOTFILES/$hook"
    if grep -qs leak-check "$hook"; then
        log "ok      leak-check pre-commit hook"
        return 0
    fi
    [ -e "$hook" ] && { warn "own pre-commit hook present, add: lib/leak-check.sh"; return 0; }
    run mkdir -p "$(dirname "$hook")"
    [ "$DRY_RUN" = 1 ] || printf '#!/bin/sh\nexec "$(git rev-parse --show-toplevel)/lib/leak-check.sh"\n' > "$hook"
    run chmod +x "$hook"
    log "hook    leak-check pre-commit"
}

# Depth-first dependency resolution; ORDER ends up deps-first, no repeats.
ORDER=()
resolve() {
    local m="$1" dep
    [ -d "$DOTFILES/modules/$m" ] || { echo "unknown module: $m" >&2; exit 1; }
    [[ " ${ORDER[*]} " == *" $m "* ]] && return 0
    for dep in $(module_field "$m" DEPENDS); do
        resolve "$dep"
    done
    ORDER+=("$m")
}

# Module checklist. The preset's modules start ticked.
pick_with_fzf() {
    local i=0 m bind="" header='TAB select, ENTER apply'
    ensure_fzf
    if [ -n "$CHOSEN_PRESET" ]; then
        for m in $(all_modules); do
            i=$((i + 1))
            [[ " $(preset_field "$CHOSEN_PRESET" MODULES) " == *" $m "* ]] && bind+="pos($i)+select+"
        done
        header="preset $CHOSEN_PRESET ticked. TAB toggle, ENTER apply"
    fi
    list_modules | fzf --multi --reverse --height=60% \
        --prompt='modules> ' --header="$header" \
        ${bind:+--bind "load:${bind}first"} |
        awk '{print $1}'
}

# Tick the packages to install. Nothing is preselected. The ticked "kind item"
# lines go to $PKG_PICK_FILE, which the install helpers in lib/common.sh read.
pick_packages() {
    local m kind item
    local -a rows=()
    for m in "${ORDER[@]}"; do
        for kind in apt snap flatpak; do
            [ -f "$DOTFILES/modules/$m/packages.$kind" ] || continue
            while IFS= read -r item; do
                rows+=("$kind"$'\t'"$item"$'\t'"$m")
            done < <(pkg_items "$kind" "$DOTFILES/modules/$m/packages.$kind")
        done
    done
    [ "${#rows[@]}" -eq 0 ] && { : > "$PKG_PICK_FILE"; return 0; }

    printf '%s\n' "${rows[@]}" | fzf --multi --reverse --height=80% \
        --delimiter=$'\t' --with-nth=1,2,3 --prompt='packages> ' \
        --header='TAB tick, ENTER install ticked, ESC install none' |
        awk -F'\t' 'NF >= 2 { print $1 " " $2 }' > "$PKG_PICK_FILE" || true
}

# Merge one package kind across the selected modules into a single list file.
merged_list() {
    local m f
    for m in "${ORDER[@]}"; do
        f="$DOTFILES/modules/$m/packages.$1"
        [ -f "$f" ] && { cat "$f"; echo; }
    done > "$WORK/all.$1"
    printf '%s' "$WORK/all.$1"
}

# All ticked packages in one pass instead of one apt run per module. apt runs
# in the foreground; snaps and flatpaks download in the background into logs
# and keep going while the modules run (Flathub can be slow, and no module
# needs those apps to apply). wait_packages collects them at the end.
declare -A PKG_JOBS=()
install_packages() {
    local apt snap flat rc=0
    apt="$(merged_list apt)" snap="$(merged_list snap)" flat="$(merged_list flatpak)"

    printf '\n\033[1m==> packages\033[0m\n'
    snap_install "$snap" > "$WORK/snap.log" 2>&1 & PKG_JOBS[$!]=snap
    # flatpak itself comes from apt on a fresh machine, so wait for apt then.
    if command -v flatpak >/dev/null; then
        flatpak_install "$flat" > "$WORK/flatpak.log" 2>&1 & PKG_JOBS[$!]=flatpak
    fi
    apt_install "$apt" || rc=1
    if [[ " ${PKG_JOBS[*]} " != *" flatpak "* ]]; then
        flatpak_install "$flat" > "$WORK/flatpak.log" 2>&1 & PKG_JOBS[$!]=flatpak
    fi
    [ "${#PKG_JOBS[@]}" -eq 0 ] || printf '    \033[2msnaps and flatpaks continue in the background\033[0m\n'
    return "$rc"
}

wait_packages() {
    local pid name rc=0
    [ "${#PKG_JOBS[@]}" -eq 0 ] && return 0
    printf '\n\033[1m==> snaps and flatpaks\033[0m  (still downloading, waiting)\n'
    for pid in "${!PKG_JOBS[@]}"; do
        name="${PKG_JOBS[$pid]}"
        wait "$pid" || { rc=1; warn "$name install failed"; }
        [ -s "$WORK/$name.log" ] && cat "$WORK/$name.log"
    done
    PKG_JOBS=()
    return "$rc"
}

# Run modules as soon as their DEPENDS finish, up to MAX_JOBS at once, never
# two holding the same LOCKS name. Each module's output goes to a log that is
# printed when it finishes, so parallel output never interleaves.
declare -A STATUS=()
run_modules() {
    local m dep lock ready pid rc started
    local -a pending=("$@")
    local -A pid_mod=() held=() t0=()
    local failed=0 stop=0
    for m in "$@"; do STATUS[$m]=pending; done

    while [ "${#pending[@]}" -gt 0 ] || [ "${#pid_mod[@]}" -gt 0 ]; do
        # Start everything that is ready, in ORDER order.
        local -a still=()
        for m in "${pending[@]}"; do
            ready=1
            for dep in $(module_field "$m" DEPENDS); do
                # Unset means the dep is outside this run (apt-repos, done earlier).
                case "${STATUS[$dep]:-ok}" in
                    ok) ;;
                    FAILED|skipped) STATUS[$m]=skipped; ready=skip ;;
                    *) ready=0 ;;
                esac
            done
            [ "$ready" = skip ] && continue
            for lock in $(module_field "$m" LOCKS); do
                [ -n "${held[$lock]:-}" ] && ready=0
            done
            if [ "$ready" = 0 ] || [ "$stop" = 1 ] || [ "${#pid_mod[@]}" -ge "$MAX_JOBS" ]; then
                still+=("$m")
                continue
            fi
            for lock in $(module_field "$m" LOCKS); do held[$lock]="$m"; done
            STATUS[$m]=running
            t0[$m]="$SECONDS"
            if [ "$MAX_JOBS" = 1 ]; then
                printf '\n\033[1m==> %s\033[0m\n' "$m"
                bash "$DOTFILES/modules/$m/apply.sh" < /dev/null &
            else
                bash "$DOTFILES/modules/$m/apply.sh" < /dev/null > "$WORK/$m.log" 2>&1 &
            fi
            pid_mod[$!]="$m"
        done
        pending=("${still[@]}")
        if [ "$stop" = 1 ]; then
            for m in "${pending[@]}"; do STATUS[$m]="not run"; done
            pending=()
        fi
        [ "${#pid_mod[@]}" -eq 0 ] && break
        if [ "$MAX_JOBS" -gt 1 ]; then
            started=""
            for m in "${pid_mod[@]}"; do started+=" $m"; done
            printf '    \033[2mrunning:%s\033[0m\n' "$started"
        fi

        if wait -n -p pid "${!pid_mod[@]}"; then rc=0; else rc=$?; fi
        m="${pid_mod[$pid]}"
        unset "pid_mod[$pid]"
        for lock in $(module_field "$m" LOCKS); do unset "held[$lock]"; done
        if [ "$rc" = 0 ]; then
            STATUS[$m]=ok
        else
            STATUS[$m]=FAILED
            failed=1
            [ "$KEEP_GOING" = 1 ] || stop=1
        fi

        if [ "$MAX_JOBS" -gt 1 ]; then
            printf '\n\033[1m==> %s\033[0m  %s, %ss\n' "$m" "${STATUS[$m]}" "$((SECONDS - t0[$m]))"
            cat "$WORK/$m.log"
        fi
    done
    [ "$failed" = 0 ]
}

# Off Zorin, the modules swap Zorin themes and extensions for the stand-ins in
# zorin-deps.txt. Say so once, so the swap is not a surprise.
report_distro() {
    is_zorin && return 0
    printf '\n\033[33m! not Zorin: Zorin themes/extensions are swapped per zorin-deps.txt\033[0m\n'
}

summary() {
    local m
    printf '\n%-18s %s\n' "module" "result"
    for m in "${ORDER[@]}"; do
        printf '%-18s %s\n' "$m" "${STATUS[$m]:-not run}"
    done
}

SELECTED=()
PRESET_ARG=""
THEME_ARG=""
LOCK_ARG=""
SETUP=0
ALL_PACKAGES=0
KEEP_GOING=0
MAX_JOBS=8
while [ $# -gt 0 ]; do
    case "$1" in
        --list)         printf 'MODULES\n'; list_modules
                        printf '\nPRESETS (--preset)\n'; list_presets
                        printf '\nTHEMES (--theme)\n'; list_themes; exit 0 ;;
        --preset)       PRESET_ARG="$2"; shift ;;
        --theme)        THEME_ARG="$2"; shift ;;
        --lockscreen)   LOCK_ARG="$2"; shift ;;
        --setup)        SETUP=1 ;;
        --all)          mapfile -t SELECTED < <(all_modules) ;;
        --only)         IFS=, read -ra SELECTED <<< "$2"; shift ;;
        --dry-run)      DRY_RUN=1 ;;
        --all-packages) ALL_PACKAGES=1 ;;
        --serial)       MAX_JOBS=1 ;;
        --keep-going)   KEEP_GOING=1 ;;
        -h|--help)      usage ;;
        *)              usage 1 ;;
    esac
    shift
done
export DRY_RUN TS

setup_private

# Preset: the flag, else the saved one, else ask (terminal only).
CHOSEN_PRESET="$PRESET_ARG"
PRESET_FROM_FLAG=0
[ -n "$PRESET_ARG" ] && PRESET_FROM_FLAG=1
[ -n "$CHOSEN_PRESET" ] || [ "$SETUP" = 1 ] || CHOSEN_PRESET="$(conf_get PRESET)"
if [ -z "$CHOSEN_PRESET" ] && [ -t 0 ]; then
    CHOSEN_PRESET="$(pick_preset)"
    PRESET_ARG="$CHOSEN_PRESET"
fi
if [ -n "$CHOSEN_PRESET" ]; then
    [ -f "$DOTFILES/presets/$CHOSEN_PRESET.env" ] ||
        { echo "unknown preset: $CHOSEN_PRESET (have: $(list_presets | awk '{print $1}' | paste -sd' '))" >&2; exit 1; }
    if [ -n "$PRESET_ARG" ]; then
        echo "preset: $CHOSEN_PRESET"
        local_env_set PRESET "$CHOSEN_PRESET"
        local_env_set PROFILE "$(preset_field "$CHOSEN_PRESET" PROFILE)"
        local_env_set CONKY_WIDGETS "$(preset_field "$CHOSEN_PRESET" CONKY_WIDGETS)"
    fi
fi

# Modules: --only/--all, else the picker, else (no terminal) the preset's list.
if [ "${#SELECTED[@]}" -eq 0 ]; then
    # --preset on the command line means "that preset's modules", no picker.
    if [ "$PRESET_FROM_FLAG" = 1 ] || { [ -n "$CHOSEN_PRESET" ] && [ ! -t 0 ]; }; then
        read -ra SELECTED <<< "$(preset_field "$CHOSEN_PRESET" MODULES)"
    else
        mapfile -t SELECTED < <(pick_with_fzf)
    fi
fi
[ "${#SELECTED[@]}" -eq 0 ] && { echo "nothing selected"; exit 0; }

for m in "${SELECTED[@]}"; do
    resolve "$m"
done

# Theme and lock screen: flags win; the pickers show only when rice runs and
# nothing is saved yet (or --setup).
if [ -z "$THEME_ARG" ] && [ -t 0 ] && [[ " ${ORDER[*]} " == *" rice "* ]] &&
    { [ "$SETUP" = 1 ] || [ -z "$(conf_get RICE_THEME)" ]; }; then
    THEME_ARG="$(pick_theme)"
fi
if [ -n "$THEME_ARG" ]; then
    [ -f "$DOTFILES/modules/rice/themes/$THEME_ARG.palette" ] ||
        { echo "unknown theme: $THEME_ARG (have: $(list_themes | awk '{print $1}' | paste -sd' '))" >&2; exit 1; }
    local_env_set RICE_THEME "$THEME_ARG"
fi
if [ -z "$LOCK_ARG" ] && [ -t 0 ] && [[ " ${ORDER[*]} " == *" rice "* ]] &&
    { [ "$SETUP" = 1 ] || [ -z "$(conf_get RICE_LOCKSCREEN)" ]; }; then
    LOCK_ARG="$(pick_lockscreen)"
fi
if [ -n "$LOCK_ARG" ]; then
    case "$LOCK_ARG" in grid|rain) ;; *) echo "unknown lock screen: $LOCK_ARG (grid or rain)" >&2; exit 1 ;; esac
    local_env_set RICE_LOCKSCREEN "$LOCK_ARG"
fi

echo "modules: ${ORDER[*]}"
[ "$DRY_RUN" = 1 ] && echo "(dry run, nothing will change)"
report_distro

WORK="$(mktemp -d)"
SUDO_KEEPALIVE=""
cleanup() {
    [ -n "$SUDO_KEEPALIVE" ] && kill "$SUDO_KEEPALIVE" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

PKG_PICK_FILE=""
if [ "$ALL_PACKAGES" = 0 ]; then
    [ -t 0 ] || { echo "the package picker needs a terminal (or pass --all-packages)" >&2; exit 1; }
    PKG_PICK_FILE="$WORK/picked"
    pick_packages
    echo "ticked $(wc -l < "$PKG_PICK_FILE") package(s), the rest are skipped"
fi
export PKG_PICK_FILE

# One password prompt, then keep sudo fresh so parallel jobs never ask again.
if [ "$DRY_RUN" != 1 ]; then
    sudo -v
    ( while kill -0 $$ 2>/dev/null && sudo -n true 2>/dev/null; do sleep 50; done ) &
    SUDO_KEEPALIVE=$!
fi

REST=()
for m in "${ORDER[@]}"; do
    [ "$m" = apt-repos ] || REST+=("$m")
done

# apt-repos first: the package step needs its sources and apt-get update.
if [ "${#REST[@]}" -lt "${#ORDER[@]}" ]; then
    MAX_JOBS_SAVED="$MAX_JOBS"; MAX_JOBS=1
    run_modules apt-repos || { summary; exit 1; }
    MAX_JOBS="$MAX_JOBS_SAVED"
fi

if ! install_packages; then
    if [ "$KEEP_GOING" = 1 ]; then
        warn "package install failed, running the modules anyway"
    else
        wait_packages || true
        summary
        echo "package install failed, modules not run" >&2
        exit 1
    fi
fi
# Modules' own apt/snap/flatpak calls are now covered; make them no-ops.
export PKGS_INSTALLED=1

rc=0
[ "${#REST[@]}" -eq 0 ] || run_modules "${REST[@]}" || rc=1
wait_packages || rc=1
summary
exit "$rc"
