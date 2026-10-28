#!/usr/bin/env bash
# 64-default-apps.sh — Set default apps from configs/macos/default-apps.conf.
#
#   <bundle-id>  <url-scheme>                  e.g. com.brave.Browser  https
#   <bundle-id>  <uniform-type-id>  <role>     e.g. md.obsidian  net.daringfireball.markdown  all
#
# Each handler is read first (`duti -d`) and only set when it differs. Before
# setting one, the app is registered with Launch Services (`lsregister -f`):
# an app installed moments earlier by Homebrew isn't known to macOS yet, and
# making it a default then silently does nothing. macOS asks you to confirm a
# new default web browser; until you do, the old one stays, and this module
# leaves a follow-up rather than reporting success.
#
# Usage: scripts/64-default-apps.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/macos/default-apps.conf"
# A new default browser makes macOS show a confirmation dialog, and duti waits
# for the answer; past this many seconds it becomes a follow-up instead.
TIMEOUT="${OMAMAS_PROMPT_TIMEOUT:-30}"
LSREGISTER=$(test_override OMAMAS_LSREGISTER /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister)
# Where apps are looked up by bundle id (OMAMAS_APPLICATIONS_DIR narrows it for tests).
if [[ -n ${OMAMAS_APPLICATIONS_DIR:-} ]]; then
  APP_DIRS=("$OMAMAS_APPLICATIONS_DIR")
else
  APP_DIRS=(/Applications /System/Applications "$HOME/Applications")
fi
REGISTERED=" "

# Bundle id currently handling TARGET (empty if none).
handler_for() { duti -d "$1" 2>/dev/null | head -n1 || true; }

# Path of the installed app whose bundle id is ID (case-insensitive).
app_for_id() {
  local want dir app
  want=$(lower "$1")
  for dir in "${APP_DIRS[@]}"; do
    for app in "$dir"/*.app; do
      [[ -d $app ]] || continue
      if [[ $(lower "$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)") == "$want" ]]; then
        printf '%s' "$app"
        return 0
      fi
    done
  done
  return 1
}

# Make sure Launch Services knows the app with bundle id ID (once per run).
register_app() {
  local id=$1 app
  [[ $REGISTERED != *" $(lower "$id") "* ]] || return 0
  app=$(app_for_id "$id") || return 1
  "$LSREGISTER" -f "$app" >/dev/null 2>&1 || true
  REGISTERED+="$(lower "$id") "
}

main() {
  module_start "$@"
  require_macos
  if [[ ! -f $MANIFEST ]]; then
    log_skip "No $(tildify "$MANIFEST")"
    module_finish
    return 0
  fi
  ensure_brew_shellenv || true
  require_cmd duti "It's in the Brewfile; run scripts/20-packages.sh first."

  local id target role have rc pending=""
  while read -r id target role; do
    have=$(handler_for "$target")
    if [[ $(lower "$have") == "$(lower "$id")" ]]; then
      log_skip "$target → $id"
      continue
    fi
    if is_dry_run; then
      log_dry "$target: ${have:-none} → $id"
      continue
    fi
    if ! register_app "$id"; then
      log_error "$target: no app with bundle id $id is installed"
      continue
    fi
    rc=0
    run_with_timeout "$TIMEOUT" duti -s "$id" "$target" ${role:+"$role"} 2>/dev/null || rc=$?
    if [[ $(lower "$(handler_for "$target")") == "$(lower "$id")" ]]; then
      log_success "$target → $id (was: ${have:-none})"
    elif [[ -z $role && ($target == http || $target == https || $rc == 0 || $rc == 142) ]]; then
      # Link types (no role): a new default browser waits for your confirmation,
      # and https can't be set while that dialog for http is still open, so
      # its error means "pending", not "broken".
      log_warn "$target: waiting for you to confirm $id in macOS's dialog"
      pending+="$target "
    elif ((rc == 0 || rc == 142)); then
      log_warn "$target: macOS hasn't applied $id yet"
      pending+="$target "
    else
      log_error "Couldn't set $target → $id (duti exited $rc)"
    fi
  done < <(read_manifest "$MANIFEST")

  if [[ -n $pending ]]; then
    add_note "Default apps not applied yet: ${pending% }. Confirm any macOS dialog, then: ./setup.sh --only default-apps"
  fi
  module_finish
}

main "$@"
