#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/cli-tools"
F="$MOD/files"

apt_install "$MOD/packages.apt"
snap_install "$MOD/packages.snap"

# atuin comes from apt where the release packages it (Ubuntu 25.04+); older
# ones use the upstream installer. --non-interactive: it otherwise prompts on
# /dev/tty, which a parallel module run does not have.
# --no-modify-path: cli-tools.bash puts ~/.atuin/bin on PATH itself.
if ! command -v atuin >/dev/null && [ ! -x "$HOME/.atuin/bin/atuin" ] &&
    apt-cache policy atuin 2>/dev/null | grep -q 'Candidate: [0-9]'; then
    run sudo apt-get install -y atuin
    run atuin import auto
elif ! command -v atuin >/dev/null && [ ! -x "$HOME/.atuin/bin/atuin" ]; then
    run sh -c 'curl --proto =https --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive --no-modify-path'
    run "$HOME/.atuin/bin/atuin" import auto
fi

link_file "$F/cli-tools.bash" "$HOME/.config/bash/cli-tools.bash"
link_file "$F/delta.gitconfig" "$HOME/.config/git/delta.gitconfig"
link_file "$F/lazygit.yml" "$HOME/.config/lazygit/config.yml"
link_file "$F/yazi/yazi.toml" "$HOME/.config/yazi/yazi.toml"
link_file "$F/yazi/package.toml" "$HOME/.config/yazi/package.toml"

# Plugins pinned in package.toml (piper: glow-rendered markdown preview).
command -v ya >/dev/null && run ya pkg install

# Real bat/fd names on PATH (not aliases): fzf previews, yazi and scripts
# call `bat` and `fd` directly, and aliases only exist in interactive bash.
for pair in batcat:bat fdfind:fd; do
    real="/usr/bin/${pair%%:*}"
    [ -x "$real" ] && link_file "$real" "$HOME/.local/bin/${pair##*:}"
done

# watchexec is in neither apt nor snap: built from crates.io with rustup.
# --locked uses the versions the authors tested, not the newest resolvable.
if command -v cargo >/dev/null; then
    for pair in watchexec:watchexec-cli; do
        if command -v "${pair%%:*}" >/dev/null; then
            log "ok      ${pair%%:*}"
        else
            run cargo install --locked "${pair##*:}"
        fi
    done
else
    log "skip    watchexec: no cargo (apply the dev module first)"
fi

# Fresh (terminal editor) is not in apt or snap. The release tarball holds one
# static-enough binary, so use it instead of `cargo install` (its Deno/V8 plugin
# runtime makes a source build slow). The .sha256 is checked before install.
# Only x86_64 is wired up; the robots (aarch64) skip it.
if command -v fresh >/dev/null; then
    log "ok      fresh"
elif [ "$(uname -m)" != x86_64 ]; then
    log "skip    fresh: no x86_64 release build for $(uname -m) wired up"
elif [ "$DRY_RUN" = 1 ]; then
    log "[dry] install fresh release tarball to ~/.local/bin/fresh"
else
    FRESH_NAME=fresh-editor-x86_64-unknown-linux-gnu
    FRESH_URL=https://github.com/sinelaw/fresh/releases/latest/download
    FRESH_TMP="$(mktemp -d)"
    (
        cd "$FRESH_TMP"
        curl -fsSLO "$FRESH_URL/$FRESH_NAME.tar.xz"
        curl -fsSLO "$FRESH_URL/$FRESH_NAME.tar.xz.sha256"
        sha256sum -c "$FRESH_NAME.tar.xz.sha256"
        tar -xJf "$FRESH_NAME.tar.xz"
        mkdir -p "$HOME/.local/bin"
        install -m 0755 "$FRESH_NAME/fresh" "$HOME/.local/bin/fresh"
    ) && log "install fresh -> ~/.local/bin/fresh" || warn "fresh install failed"
    rm -rf "$FRESH_TMP"
fi

# tealdeer starts with an empty page cache; fetch it once.
if command -v tldr >/dev/null && [ ! -d "$HOME/.cache/tealdeer/tldr-pages" ]; then
    run tldr --update
fi

# Live ~/.bashrc may not be the shell module's symlink, so hook into whichever file is there.
SRC_LINE='[ -f ~/.config/bash/cli-tools.bash ] && . ~/.config/bash/cli-tools.bash'
if grep -qxF "$SRC_LINE" "$HOME/.bashrc"; then
    log "ok      ~/.bashrc hook"
elif grep -q 'ble-attach' "$HOME/.bashrc"; then
    run sed -i "/ble-attach/i $SRC_LINE" "$HOME/.bashrc"
    log "hook    ~/.bashrc (before ble-attach)"
else
    run sh -c "printf '%s\n' '$SRC_LINE' >> '$HOME/.bashrc'"
    log "hook    ~/.bashrc"
fi

# gitconfig already includes it as ~/.config/git/delta.gitconfig; older
# copies used the absolute path. Add it only when neither form is there.
INC="$HOME/.config/git/delta.gitconfig"
if git config --global --get-all include.path | grep -qxE "($HOME|~)/\.config/git/delta\.gitconfig"; then
    log "ok      gitconfig include"
else
    run git config --global --add include.path "$INC"
    log "include $INC"
fi
