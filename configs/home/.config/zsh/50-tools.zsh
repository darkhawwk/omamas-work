# Editors: terminal editor for EDITOR and sudoedit, CotEditor for VISUAL.
# `cot -w` waits until the file is closed, which git and friends require.
export EDITOR=nvim
export SUDO_EDITOR=$EDITOR
command -v cot &> /dev/null && export VISUAL="cot -w"

export BAT_THEME=ansi

# 1Password's SSH agent for every tool. ssh and git already use it through
# ~/.ssh/config, but ssh-add, git GUIs and editors only read SSH_AUTH_SOCK.
_op_agent="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
[[ -S $_op_agent ]] && export SSH_AUTH_SOCK=$_op_agent
unset _op_agent

# mise (runtime version manager)
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh --quiet)"
fi

# zoxide (smart cd; provides `z`, used by zd in 40-aliases.zsh)
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
fi

# fzf key bindings and completion (built into fzf >= 0.48)
if command -v fzf &> /dev/null; then
  source <(fzf --zsh)
fi

# Prompt
if command -v starship &> /dev/null; then
  eval "$(starship init zsh)"
fi
