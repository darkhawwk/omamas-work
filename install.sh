#!/usr/bin/env bash
# install.sh — Omamas remote bootstrap.
#
#   curl -fsSL https://raw.githubusercontent.com/thebenwalther/omamas/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --dry-run      # pass flags to setup.sh
#
# Ensures the Xcode Command Line Tools (for git), clones or fast-forwards the
# repo, then hands control to setup.sh. Deliberately self-contained: it runs
# before the repo (and therefore utils.sh) exists on disk.
#
# Environment overrides:
#   OMAMAS_REPO   git URL   (default: https://github.com/thebenwalther/omamas.git)
#   OMAMAS_REF    branch    (default: main)
#   OMAMAS_DIR    checkout  (default: ~/.local/share/omamas)

# Everything lives in functions and main runs on the last line, so a download
# cut short by the network can never execute a partial script.

set -euo pipefail

OMAMAS_REPO="${OMAMAS_REPO:-https://github.com/thebenwalther/omamas.git}"
OMAMAS_REF="${OMAMAS_REF:-main}"
OMAMAS_DIR="${OMAMAS_DIR:-$HOME/.local/share/omamas}"

say() { printf '\033[1;34m[omamas]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[omamas]\033[0m %s\n' "$*" >&2; }
fail() {
  printf '\033[1;31m[omamas] ERROR:\033[0m %s\n' "$*" >&2
  exit 1
}

check_platform() {
  [[ $(uname -s) == Darwin ]] || fail "Omamas only supports macOS."
  [[ $EUID -ne 0 ]] || fail "Run as your normal user, not root."
}

clt_installed() { xcode-select -p >/dev/null 2>&1 && /usr/bin/xcrun --find git >/dev/null 2>&1; }

install_clt() {
  clt_installed && { say "Command Line Tools present."; return 0; }
  say "Installing Xcode Command Line Tools (needs your password)..."

  # Headless path: the placeholder file makes softwareupdate list the CLT.
  # /tmp is shared: if something pre-planted a symlink here, a root `touch`
  # would follow it and create a file wherever it points. Refuse that case, and
  # use touch -h, which never follows a symlink, to close the race too.
  local marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
  [[ ! -L $marker ]] || fail "$marker is a symlink; refusing to touch it as root."
  sudo touch -h "$marker"
  label=$(softwareupdate -l 2>/dev/null |
    sed -n 's/^[[:space:]]*\* Label: \(Command Line Tools.*\)$/\1/p' | tail -n1)
  if [[ -n $label ]]; then
    sudo softwareupdate -i "$label" --verbose || true
  fi
  sudo rm -f "$marker"

  # Fallback: Apple's GUI installer, then wait for it to finish.
  if ! clt_installed; then
    warn "Headless install unavailable; follow the dialog that is opening."
    xcode-select --install >/dev/null 2>&1 || true
    until clt_installed; do sleep 5; done
  fi
  say "Command Line Tools installed."
}

sync_repo() {
  if [[ -d $OMAMAS_DIR/.git ]]; then
    if [[ -n $(git -C "$OMAMAS_DIR" status --porcelain) ]]; then
      warn "Local changes in $OMAMAS_DIR; skipping update and using it as-is."
      return 0
    fi
    say "Updating $OMAMAS_DIR ($OMAMAS_REF)..."
    git -C "$OMAMAS_DIR" fetch --quiet origin "$OMAMAS_REF"
    git -C "$OMAMAS_DIR" checkout --quiet "$OMAMAS_REF"
    git -C "$OMAMAS_DIR" merge --ff-only --quiet "origin/$OMAMAS_REF" ||
      warn "Could not fast-forward $OMAMAS_REF; using local state."
  elif [[ -e $OMAMAS_DIR ]]; then
    fail "$OMAMAS_DIR exists but is not a git checkout. Move it aside or set OMAMAS_DIR."
  else
    say "Cloning $OMAMAS_REPO → $OMAMAS_DIR"
    mkdir -p "$(dirname "$OMAMAS_DIR")"
    git clone --quiet --branch "$OMAMAS_REF" "$OMAMAS_REPO" "$OMAMAS_DIR"
  fi
}

main() {
  check_platform
  install_clt
  sync_repo

  say "Handing off to setup.sh"
  # Under `curl | bash` stdin is the script itself; give setup.sh the terminal
  # so prompts work. In non-interactive contexts (CI) keep stdin as-is.
  if (exec </dev/tty) 2>/dev/null; then
    exec /bin/bash "$OMAMAS_DIR/setup.sh" "$@" </dev/tty
  fi
  exec /bin/bash "$OMAMAS_DIR/setup.sh" "$@"
}

main "$@"
