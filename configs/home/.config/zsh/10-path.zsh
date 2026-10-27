# PATH additions, highest priority first. typeset -U drops duplicates, so
# nested shells don't keep growing PATH.
typeset -U path

path=(
  "$HOME/bin"
  "$HOME/.local/bin"
  $path
)

[[ -d "$HOME/.grok/bin" ]] && path=("$HOME/.grok/bin" $path)
