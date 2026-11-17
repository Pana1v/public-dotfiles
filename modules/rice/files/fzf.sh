# Tokyo Night colors for fzf; sourced from ~/.bashrc.
export FZF_DEFAULT_OPTS="--color=bg+:#2a0c0e,bg:-1,spinner:#ff3b3b,hl:#ff3d6b,fg:#f5c6c6,header:#d10a10,info:#ffb84a,pointer:#ff3b3b,marker:#ff7070,fg+:#ffe9e9,prompt:#d10a10,hl+:#ff3d6b,border:#2a0c0e --border=rounded"

# fd respects .gitignore and is much faster than find on ROS workspaces.
export FZF_DEFAULT_COMMAND="fdfind --type f --hidden --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fdfind --type d --hidden --exclude .git"

# Previews: file head for Ctrl-T, tree for Alt-C, full command for Ctrl-R.
export FZF_CTRL_T_OPTS="--preview 'head -200 {}' --preview-window right:60%"
export FZF_ALT_C_OPTS="--preview 'tree -C -L 2 {} | head -200'"
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window down:3:wrap"

# key bindings and completion come from `fzf --bash` in ~/.bashrc
