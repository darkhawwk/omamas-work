#!/usr/bin/env bash
# 07-rosetta.sh — Install Rosetta 2 on Apple silicon if it is missing.
#
# Apple-silicon Macs ship without Rosetta, and any Intel-only cask in the
# Brewfile fails to install until it is present, so this runs before Homebrew.
# Installing it non-interactively accepts Apple's Rosetta license
# (`softwareupdate --agree-to-license`). Intel Macs need nothing.
#
# Usage: scripts/07-rosetta.sh [--dry-run] [--help]

# omamas: requires-sudo

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Ask the hardware, not `uname -m`: a shell running under Rosetta reports x86_64.
is_apple_silicon() { [[ $(sysctl -n hw.optional.arm64 2>/dev/null) == 1 ]]; }

# Rosetta works if an Intel binary actually runs; no file layout assumptions.
rosetta_works() { arch -x86_64 /usr/bin/true >/dev/null 2>&1; }

main() {
  module_start "$@"
  require_macos

  if ! is_apple_silicon; then
    log_skip "Intel Mac: Rosetta not needed"
  elif rosetta_works; then
    log_skip "Rosetta 2 installed"
  elif is_dry_run; then
    log_dry "install Rosetta 2 (softwareupdate --install-rosetta --agree-to-license)"
  else
    require_sudo
    if sudo softwareupdate --install-rosetta --agree-to-license && rosetta_works; then
      log_success "Installed Rosetta 2"
    else
      log_error "Rosetta 2 installation failed; Intel-only apps will not install"
    fi
  fi

  module_finish
}

main "$@"
