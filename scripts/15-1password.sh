#!/usr/bin/env bash
# 15-1password.sh — Install 1Password early and open it for sign-in.
#
# Runs right after Homebrew so you can sign in while the long package step
# runs; it never waits for you. 1Password holds the SSH keys that git over SSH
# depends on (configs/home/.ssh/config points at its agent).
#
#   Installed by Homebrew          → SKIP
#   Installed by hand              → adopt it into Homebrew (no reinstall), so
#                                    the Brewfile's `cask "1password"` holds
#   Missing                        → install the cask, then open the app
#
# Usage: scripts/15-1password.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

CASK=1password
APP="${OMAMAS_1PASSWORD_APP:-/Applications/1Password.app}" # overridable for tests

# Open the app and leave a follow-up for the run summary. `open` is detached:
# on a freshly downloaded app macOS first asks "…downloaded from the
# Internet. Are you sure you want to open it?", and `open` waits for that
# answer, which would stall the whole run until someone clicks.
open_for_sign_in() {
  (open "$APP" >/dev/null 2>&1 &)
  log_info "Opening 1Password: confirm macOS's prompt if it asks, then sign in. Setup continues meanwhile."
  add_note "Sign in to 1Password and turn on its SSH agent (Settings → Developer) so git over SSH works."
}

main() {
  module_start "$@"
  require_macos
  ensure_brew_shellenv || die "Homebrew is not installed. Run scripts/10-homebrew.sh first."

  if brew list --cask "$CASK" >/dev/null 2>&1; then
    log_skip "1Password installed (Homebrew)"
  elif [[ -d $APP ]]; then
    # --adopt takes over an identical existing app instead of reinstalling it.
    if is_dry_run; then
      log_dry "adopt the existing $(tildify "$APP") into Homebrew"
    elif brew install --cask --adopt "$CASK"; then
      log_success "Adopted existing 1Password into Homebrew"
    else
      log_error "1Password was installed outside Homebrew and differs from the current cask. Update it (1Password → Check for Updates) and re-run."
    fi
  elif is_dry_run; then
    log_dry "install 1Password (brew install --cask $CASK) and open it for sign-in"
  elif brew install --cask "$CASK"; then
    log_success "Installed 1Password"
    open_for_sign_in
  else
    log_error "1Password installation failed"
  fi

  module_finish
}

main "$@"
