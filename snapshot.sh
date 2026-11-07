#!/usr/bin/env bash
# Pull state that cannot be symlinked from this machine into the repo:
# dconf, GNOME extensions, editor extension lists, Obsidian config, apt repos,
# and (into private/) the private dconf sections and claude.ai-synced skills.
# Symlinked modules (shell, tmux, conky, ...) need no snapshot: edits already
# land in the repo. Review with `git diff` and commit by hand.
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
M="$DOTFILES/modules"
OBSIDIAN_VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/ObsidianNotes}"

# Home paths become @HOME@ so apply.sh can put back the target machine's $HOME.
home_token() { sed "s#$HOME#@HOME@#g"; }

snap_dconf() {
    local name path excludes wall
    echo "dconf"
    excludes="$(sed -e 's/#.*//' -e '/^\s*$/d' "$M/gnome/exclude-keys.txt" | paste -sd'|')"

    # Sections listed in private-sections.txt (paired phone, weather location)
    # go to private/gnome/dconf/; without the private repo they are dropped.
    local tmp priv
    tmp="$(mktemp)"
    while read -r name path; do
        dconf dump "$path" | grep -Ev "^(${excludes})=" | home_token > "$tmp"
        priv="$DOTFILES/private/gnome/dconf/$name.ini"
        [ -f "$DOTFILES/private/private.env" ] || priv="$(mktemp -u)"
        python3 -I "$DOTFILES/lib/dconf_split.py" "$M/gnome/private-sections.txt" "$tmp" \
            "$M/gnome/dconf/$name.ini" "$priv"
        [ -f "$DOTFILES/private/private.env" ] || rm -f "$priv"
    done < <(sed -e 's/#.*//' -e '/^\s*$/d' "$M/gnome/paths.txt")
    rm -f "$tmp"

    # Ship the wallpaper itself, repointed to a path apply.sh fills.
    wall="$(gsettings get org.gnome.desktop.background picture-uri | sed "s#^'file://##; s#'\$##")"
    if [ -f "$wall" ]; then
        mkdir -p "$M/gnome/files/backgrounds"
        rm -f "$M/gnome/files/backgrounds/"*
        cp "$wall" "$M/gnome/files/backgrounds/"
        sed -i "s#file://@HOME@/[^']*#file://@HOME@/.local/share/backgrounds/$(basename "$wall")#" \
            "$M/gnome/dconf/background.ini"
    fi
}

snap_extensions() {
    echo "gnome extensions"
    rsync -a --delete --exclude='*.compiled' --exclude='.git' \
        "$HOME/.local/share/gnome-shell/extensions/" "$M/gnome-extensions/files/"
    gnome-extensions list --enabled > "$M/gnome-extensions/enabled.txt"
}

snap_editors() {
    echo "editor extension lists"
    command -v code   >/dev/null && code --list-extensions   > "$M/vscode/extensions.txt"
    command -v cursor >/dev/null && cursor --list-extensions > "$M/cursor/extensions.txt"
    return 0
}

snap_obsidian() {
    echo "obsidian config"
    # data.json holds plugin settings, and some plugins store API keys there.
    mkdir -p "$M/obsidian/files/obsidian"
    rsync -a --delete \
        --exclude='plugins/*/data.json' --exclude='workspace*.json' --exclude='.git' \
        "$OBSIDIAN_VAULT/.obsidian/" "$M/obsidian/files/obsidian/"
}

snap_apt_repos() {
    local f root="$M/apt-repos/files/root"
    echo "apt repos"
    rm -rf "$root"
    mkdir -p "$root/etc/apt/sources.list.d"

    local key codename
    while read -r f key; do
        cp "/etc/apt/sources.list.d/$f" "$root/etc/apt/sources.list.d/"
        [ -z "$key" ] && continue
        # one-line format: "deb [opts] URL" or "deb URL" gains signed-by=KEY
        sed -i -e "s#^deb \[#deb [signed-by=$key #" -e "s#^deb \([a-z]\)#deb [signed-by=$key] \1#" \
            "$root/etc/apt/sources.list.d/$f"
    done < <(sed -e 's/#.*//' -e '/^\s*$/d' "$M/apt-repos/repos.txt")

    # Release-neutral: apply.sh fills in the target machine's codename.
    codename="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
    sed -i "s/\b$codename\b/@CODENAME@/g" "$root"/etc/apt/sources.list.d/*

    # Every key file a kept repo points at, at the same absolute path.
    grep -rhoE '(signed-by=|Signed-By: )/[^] ]+' "$root/etc/apt/sources.list.d" |
        sed -E 's/^(signed-by=|Signed-By: )//' | sort -u |
        while read -r f; do
            mkdir -p "$root$(dirname "$f")"
            cp "$f" "$root$f"
        done
}

snap_skills() {
    local src
    [ -f "$DOTFILES/private/private.env" ] || return 0
    echo "skills (claude.ai sync -> private/skills)"
    for src in "$HOME"/.claude/skills/synced/*/; do
        [ -d "$src" ] || continue
        rsync -a --exclude='.*' --exclude=manifest.json "$src" "$DOTFILES/private/skills/"
    done
}

snap_dconf
snap_skills
snap_extensions
snap_editors
snap_obsidian
snap_apt_repos
echo "done. review: git -C $DOTFILES status (and git -C $DOTFILES/private status)"
