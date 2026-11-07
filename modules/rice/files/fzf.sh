# Tokyo Night colors for fzf; sourced from ~/.bashrc.
export FZF_DEFAULT_OPTS="--color=bg+:#2a1013,bg:-1,spinner:#ff6b7d,hl:#ff4f8b,fg:#f2c4c8,header:#ff1f3d,info:#ffc14d,pointer:#ff6b7d,marker:#52e5ff,fg+:#ffe9eb,prompt:#ff1f3d,hl+:#ff4f8b,border:#2a1013 --border=rounded"

# fd respects .gitignore and is much faster than find on ROS workspaces.
export FZF_DEFAULT_COMMAND="fdfind --type f --hidden --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fdfind --type d --hidden --exclude .git"

# Previews: file head for Ctrl-T, tree for Alt-C, full command for Ctrl-R.
export FZF_CTRL_T_OPTS="--preview 'head -200 {}' --preview-window right:60%"
export FZF_ALT_C_OPTS="--preview 'tree -C -L 2 {} | head -200'"
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window down:3:wrap"

# key bindings and completion come from `fzf --bash` in ~/.bashrc
