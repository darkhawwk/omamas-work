# Completion. compinit runs once, here, before any plugin that wraps it.

# Homebrew completions (normally added by `brew shellenv`; kept for safety).
if [[ -n $HOMEBREW_PREFIX ]]; then
  fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
  typeset -U fpath
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]-_}={[:upper:][:lower:]_-}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' list-colors ''
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

# Treat / as a word boundary when deleting words.
export WORDCHARS=${WORDCHARS//[\/]}

# Cache the completion dump outside the config directory.
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
[[ -d ${_zcompdump:h} ]] || mkdir -p "${_zcompdump:h}"
autoload -U compinit
compinit -d "$_zcompdump"
unset _zcompdump
