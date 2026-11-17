# shellcheck shell=bash
# Sourced from ~/.bashrc after starship and fzf, before ble-attach: atuin hooks
# into ble.sh only if it loads first, and direnv must hook the prompt last.

# bat and fd: Ubuntu ships them as batcat and fdfind. cli-tools/apply.sh links
# the short names into ~/.local/bin so scripts (fzf previews, yazi) find them too.
export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
export MANROFFOPT="-c"
export BAT_THEME=Ares   # bat/themes/Ares.tmTheme, also delta's syntax theme

# Palette hexes as 24-bit SGR codes, so rice/switch-theme.sh can recolour them.
_rice_sgr() { local h="${2#\#}"; printf '%s;2;%d;%d;%d' "$1" "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }
_rice_fg() { _rice_sgr 38 "$1"; }
_rice_bg() { _rice_sgr 48 "$1"; }

# File kinds for ls, eza, fd and tree, on top of dircolors' extension colours.
# eza takes everything else from ~/.config/eza/theme.yml.
LS_COLORS="${LS_COLORS:+$LS_COLORS:}di=1;$(_rice_fg '#d10a10'):ln=$(_rice_fg '#ff3b3b'):ex=1;$(_rice_fg '#ff7070'):fi=$(_rice_fg '#f5c6c6')"
LS_COLORS+=":pi=$(_rice_fg '#ffb84a'):so=1;$(_rice_fg '#ff3d6b'):bd=1;$(_rice_fg '#ffb84a'):cd=1;$(_rice_fg '#ffb84a')"
LS_COLORS+=":or=$(_rice_fg '#ff1a1a');$(_rice_bg '#3a0a0e'):mi=$(_rice_fg '#ff1a1a');$(_rice_bg '#3a0a0e')"
LS_COLORS+=":su=$(_rice_fg '#060101');$(_rice_bg '#ff1a1a'):sg=$(_rice_fg '#060101');$(_rice_bg '#ffb84a')"
LS_COLORS+=":tw=$(_rice_fg '#060101');$(_rice_bg '#d10a10'):ow=$(_rice_fg '#d10a10');$(_rice_bg '#2a0c0e'):st=$(_rice_fg '#060101');$(_rice_bg '#ff3d6b')"
export LS_COLORS

# less (man without bat, git help): bold, underline and the status/search bar.
export LESS_TERMCAP_md=$'\e[1;'"$(_rice_fg '#d10a10')m"
export LESS_TERMCAP_us=$'\e[4;'"$(_rice_fg '#ff3b3b')m"
export LESS_TERMCAP_so=$'\e['"$(_rice_fg '#ffe9e9');$(_rice_bg '#4a0f12')m"
export LESS_TERMCAP_mb=$'\e[1;'"$(_rice_fg '#ff3d6b')m"
export LESS_TERMCAP_me=$'\e[0m' LESS_TERMCAP_ue=$'\e[0m' LESS_TERMCAP_se=$'\e[0m'
unset -f _rice_sgr _rice_fg _rice_bg

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
