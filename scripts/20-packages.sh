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

APPS_DIR="${OMAMAS_APPLICATIONS_DIR:-/Applications}" # overridable for tests

# Version of a cask per `brew info` ("4.29.0,abc123" → "4.29.0").
cask_version() {
  brew info --cask "$1" 2>/dev/null | sed -n '1s/^==> [^:]*: \([^ ,]*\).*/\1/p'
}

# The .app bundles a cask installs, one per line.
cask_apps() {
  brew info --cask "$1" 2>/dev/null | sed -n '/^==> Artifacts/,/^==>/s/ (App)$//p'
}

# Declared casks whose app is already in /Applications but didn't come from
# Homebrew (downloaded from the vendor). brew bundle refuses to install over
# those, so: same version → adopt it, and Homebrew manages it from now on;
# different version → leave the app alone and skip the cask for this run.
handle_hand_installed_casks() {
  local cask app have want skip=""
  while IFS= read -r cask; do
    [[ -n $cask ]] || continue
    while IFS= read -r app; do
      [[ -n $app && -d $APPS_DIR/$app ]] || continue
      have=$(defaults read "$APPS_DIR/$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
      want=$(cask_version "$cask")
      if [[ -n $have && $have == "$want" ]]; then
        if is_dry_run; then
          log_dry "adopt hand-installed $app into Homebrew ($cask $want)"
          skip+="$cask "
        elif brew install --cask --adopt "$cask" >/dev/null 2>&1; then
          log_success "Adopted hand-installed $app into Homebrew ($cask $want)"
        else
          log_warn "Couldn't adopt $app into Homebrew ($cask); leaving it alone"
          skip+="$cask "
        fi
      else
        log_warn "$app was installed outside Homebrew (${have:-unknown version} vs cask ${want:-unknown}); leaving it alone. For Homebrew to manage it: quit it, then \`brew install --cask --force $cask\`"
        skip+="$cask "
      fi
      break
    done < <(cask_apps "$cask")
  done < <(comm -23 <(brew bundle list --file="$BREWFILE" --cask 2>/dev/null | sort) <(brew list --cask -1 2>/dev/null | sort))

  if [[ -n $skip ]]; then
    export HOMEBREW_BUNDLE_CASK_SKIP="${HOMEBREW_BUNDLE_CASK_SKIP:-} ${skip% }"
  fi
}

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

  handle_hand_installed_casks

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
