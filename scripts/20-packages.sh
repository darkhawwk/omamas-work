#!/usr/bin/env bash
# 20-packages.sh — Reconcile Homebrew packages with configs/Brewfile.
#
# Installs anything declared but missing. Never uninstalls: instead it reports
# drift (formulae/casks installed on request but not declared) so you can either
# declare them or remove them yourself. Outdated packages are left alone unless
# OMAMAS_UPGRADE=1, keeping routine runs predictable.
#
# Usage: scripts/20-packages.sh [--dry-run] [--help]

# omamas: requires-sudo

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

BREWFILE="$OMAMAS_CONFIG_DIR/Brewfile"

# Execution must never write into the State tier.
export HOMEBREW_BUNDLE_NO_LOCK=1 HOMEBREW_NO_ENV_HINTS=1

# Compare what is installed on request with what is declared. Read-only.
report_drift() {
  local declared installed undeclared
  declared=$(
    {
      brew bundle list --file="$BREWFILE" --formula
      brew bundle list --file="$BREWFILE" --cask
    } 2>/dev/null | sort -u
  )
  # An empty Brewfile would flag every package on the machine; that is noise.
  [[ -n $declared ]] || return 0
  installed=$({
    brew leaves --installed-on-request
    brew list --cask -1
  } 2>/dev/null | sort -u)
  undeclared=$(comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$installed"))
  if [[ -n $undeclared ]]; then
    log_warn "Drift: installed but not in Brewfile → $(printf '%s' "$undeclared" | tr '\n' ' ')"
  fi
}

main() {
  module_start "$@"
  require_macos
  ensure_brew_shellenv || die "Homebrew is not installed. Run scripts/10-homebrew.sh first."

  if [[ ! -f $BREWFILE ]]; then
    log_skip "No Brewfile at $(tildify "$BREWFILE")"
    module_finish
    return 0
  fi

  if brew bundle check --file="$BREWFILE" --no-upgrade >/dev/null 2>&1 && [[ ${OMAMAS_UPGRADE:-0} != 1 ]]; then
    log_skip "All Brewfile dependencies are installed"
  else
    local args=(bundle install --file="$BREWFILE")
    if [[ ${OMAMAS_UPGRADE:-0} == 1 ]]; then args+=(--upgrade); else args+=(--no-upgrade); fi
    # Casks frequently need an admin password mid-install.
    if grep -Eq '^[[:space:]]*cask[[:space:]]' "$BREWFILE"; then require_sudo; fi
    if run brew "${args[@]}"; then
      is_dry_run || log_success "Brewfile dependencies installed"
    else
      log_error "brew bundle install reported failures (see output above)"
    fi
  fi

  report_drift
  module_finish
}

main "$@"
