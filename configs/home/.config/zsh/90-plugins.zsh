# Plugins, installed by Homebrew (see configs/Brewfile).
# fast-syntax-highlighting must load last: it wraps every widget defined
# before it.

# opt/ paths are what Homebrew documents; they exist whenever the formula does.
_opt=${HOMEBREW_PREFIX:-/opt/homebrew}/opt

if [[ -f $_opt/zsh-autosuggestions/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source "$_opt/zsh-autosuggestions/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=60'

  # Faster pasting with autosuggestions enabled
  # https://github.com/zsh-users/zsh-autosuggestions/issues/238
  pasteinit() {
    OLD_SELF_INSERT=${${(s.:.)widgets[self-insert]}[2,3]}
    zle -N self-insert url-quote-magic
  }
  pastefinish() {
    zle -N self-insert $OLD_SELF_INSERT
  }
  zstyle :bracketed-paste-magic paste-init pasteinit
  zstyle :bracketed-paste-magic paste-finish pastefinish
fi

_fsh=$_opt/zsh-fast-syntax-highlighting/share/zsh-fast-syntax-highlighting
if [[ -f $_fsh/fast-syntax-highlighting.plugin.zsh ]]; then
  source "$_fsh/fast-syntax-highlighting.plugin.zsh"
fi

unset _opt _fsh
