#!/usr/bin/env bash
set -euo pipefail
. "$DOTFILES/lib/common.sh"
MOD="$DOTFILES/modules/apps-dev"

apt_install "$MOD/packages.apt"

if ! id -nG "$USER" | grep -qw docker; then
    run sudo usermod -aG docker "$USER"
    warn "added $USER to docker group, log out and back in"
fi

# User-level toolchains from their official installers, skipped when present.
# They write to separate dirs, so they download and install at the same time.
command -v uv     >/dev/null || spawn uv     run sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
command -v rustup >/dev/null || spawn rustup run sh -c 'curl --proto =https -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path'
command -v claude >/dev/null || spawn claude run bash -c 'curl -fsSL https://claude.ai/install.sh | bash'

if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
    # PROFILE=/dev/null: the shell module's bashrc already lazy-loads nvm.
    spawn nvm run bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null bash && . "$HOME/.nvm/nvm.sh" && nvm install 20'
fi
spawn_wait
log "ok      toolchains"
