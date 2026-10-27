# File system
alias ls='eza -lh --group-directories-first --icons=auto'
alias lsa='ls -a'
alias lt='eza --tree --level=2 --long --icons --git'
alias lta='lt -a'
alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
alias cd="zd"

# cd that falls back to zoxide for names that aren't directories here.
zd() {
  if [[ $# -eq 0 ]]; then
    builtin cd ~ && return
  elif [[ -d "$1" ]]; then
    builtin cd "$1"
  else
    z "$1" && printf "\U000F17A9 " && pwd || echo "Error: Directory not found"
  fi
}

open() {
  command open "$@" &> /dev/null &
}

# Directories
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Tools
alias d='docker'

n() {
  if [[ "$#" -eq 0 ]]; then
    nvim .
  else
    nvim "$@"
  fi
}

# Git
alias g='git'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gcad='git commit -a --amend'
