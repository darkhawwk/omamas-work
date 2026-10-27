# ~/.zprofile — login shells (every new terminal tab on macOS).

# Homebrew: PATH, MANPATH, HOMEBREW_PREFIX and its completions.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
