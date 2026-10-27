#!/usr/bin/env bash
# 10-homebrew.sh — Ensure Homebrew is installed and on PATH.
#
# Installs Homebrew non-interactively if missing. With OMAMAS_UPGRADE=1 it also
# runs `brew update`. Persisting brew on PATH for future shells is the job of
# your dotfiles (e.g. `eval "$(/opt/homebrew/bin/brew shellenv)"` in .zprofile).
#
# Usage: scripts/10-homebrew.sh [--dry-run] [--help]

# omamas: requires-sudo

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
INSTALLER_FILE=""

cleanup_installer() { [[ -z $INSTALLER_FILE ]] || rm -f "$INSTALLER_FILE"; }

install_homebrew() {
  if is_dry_run; then
    log_dry "install Homebrew from $INSTALLER_URL"
    return 0
  fi
  require_sudo

  # Download fully before executing, so a dropped connection can never run a
  # truncated installer.
  INSTALLER_FILE=$(mktemp -t omamas-brew-install) || return 1
  add_exit_hook cleanup_installer
  curl -fsSL "$INSTALLER_URL" -o "$INSTALLER_FILE" || {
    log_error "Failed to download the Homebrew installer"
    return 1
  }
  NONINTERACTIVE=1 /bin/bash "$INSTALLER_FILE" || return 1

  ensure_brew_shellenv || {
    log_error "Homebrew installed but brew was not found in a standard prefix"
    return 1
  }
  log_success "Installed Homebrew $(brew --version | head -n1)"
}

main() {
  module_start "$@"
  require_macos
  require_not_root

  if ensure_brew_shellenv; then
    log_skip "Homebrew present at $(command -v brew)"
  else
    install_homebrew || log_error "Homebrew installation failed"
  fi

  if [[ ${OMAMAS_UPGRADE:-0} == 1 ]] && has_cmd brew; then
    if run brew update --quiet; then
      log_info "Homebrew metadata updated"
    else
      log_warn "brew update failed; continuing with cached metadata"
    fi
  fi

  module_finish
}

main "$@"
