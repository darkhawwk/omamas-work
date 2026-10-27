# ~/.zshrc — interactive shells.
#
# Configuration lives in ~/.config/zsh/*.zsh, loaded in name order; add a
# feature by dropping in a new numbered file. Machine-specific settings and
# secrets go in ~/.zshrc.local, which is never committed.
#
# If an installer appends lines below, move them into a fragment or
# ~/.zshrc.local: this file is a symlink into the Omamas repo.

for config in "${XDG_CONFIG_HOME:-$HOME/.config}"/zsh/*.zsh(N); do
  source "$config"
done
unset config

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
