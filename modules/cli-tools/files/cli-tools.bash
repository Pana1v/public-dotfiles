# shellcheck shell=bash
# Sourced from ~/.bashrc after starship and fzf, before ble-attach: atuin hooks
# into ble.sh only if it loads first, and direnv must hook the prompt last.

# bat and fd: Ubuntu ships them as batcat and fdfind. cli-tools/apply.sh links
# the short names into ~/.local/bin so scripts (fzf previews, yazi) find them too.
export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
export MANROFFOPT="-c"
export BAT_THEME=ansi   # follows the terminal palette, so it recolors with the rice

alias ls='eza --group-directories-first --icons=auto'
alias ll='eza -l --git --group-directories-first --icons=auto --time-style=relative'
alias la='eza -la --git --group-directories-first --icons=auto --time-style=relative'
alias lt='eza -T --level=2 --git-ignore --icons=auto'

alias lg='lazygit'

# Ctrl-R opens atuin, up arrow stays plain bash history.
[ -d "$HOME/.atuin/bin" ] && PATH="$HOME/.atuin/bin:$PATH"
command -v atuin >/dev/null && eval "$(atuin init bash --disable-up-arrow)"

# zoxide: `z foo` jumps by frecency, `zi foo` picks with fzf. Plain cd untouched.
export _ZO_FZF_OPTS="--height=40% --layout=reverse --preview 'eza -1 --icons=always --color=always {2..}' --preview-window right:40%"
command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# yazi: `y` opens it and leaves the shell in the directory you quit from.
y() {
    local tmp cwd
    tmp="$(mktemp -t yazi-cwd.XXXXXX)"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd" || return
    fi
    rm -f -- "$tmp"
}

# direnv last: its hook diffs the environment after every other prompt hook.
export DIRENV_LOG_FORMAT=$'\e[2mdirenv: %s\e[0m'
command -v direnv >/dev/null && eval "$(direnv hook bash)"
