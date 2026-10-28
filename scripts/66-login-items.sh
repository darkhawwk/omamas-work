#!/usr/bin/env bash
# 66-login-items.sh — Open the apps in configs/macos/login-items.conf at login.
#
# Adds missing apps to System Settings → General → Login Items ("Open at
# Login") through System Events; never removes any. macOS asks once whether
# your terminal may control System Events. If that's declined or nobody
# answers within 20 seconds, the module leaves a follow-up instead of failing.
#
# Usage: scripts/66-login-items.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/macos/login-items.conf"
TIMEOUT="${OMAMAS_PROMPT_TIMEOUT:-20}" # seconds to wait on a permission prompt

# Paths of the current login items, comma-separated.
list_login_items() {
  run_with_timeout "$TIMEOUT" osascript -e 'tell application "System Events" to get the path of every login item' 2>/dev/null
}

# add_login_item PATH true|false. Values travel as script arguments (argv),
# never pasted into the script text, so no path can inject AppleScript.
add_login_item() {
  run_with_timeout "$TIMEOUT" osascript \
    -e 'on run argv' \
    -e 'tell application "System Events" to make login item at end with properties {path:(item 1 of argv), hidden:((item 2 of argv) is "true")}' \
    -e 'end run' "$1" "$2" 2>/dev/null
}

main() {
  module_start "$@"
  require_macos
  if [[ ! -f $MANIFEST ]]; then
    log_skip "No $(tildify "$MANIFEST")"
    module_finish
    return 0
  fi

  local current
  if ! current=$(list_login_items); then
    log_warn "Couldn't read login items: System Events access not granted (yet)"
    add_note "Allow your terminal to control System Events (System Settings → Privacy & Security → Automation), then: ./setup.sh --only login-items"
    module_finish
    return 0
  fi
  current=$(printf '%s\n' "$current" | /usr/bin/perl -pe 's/, /\n/g')

  local line app flag hidden
  while IFS= read -r line; do
    # Paths may contain spaces; only a trailing " hidden" is a flag.
    app=$line flag=""
    if [[ $line == *" hidden" ]]; then app=${line% hidden} flag=hidden; fi
    if [[ ! -d $app ]]; then
      log_warn "Not installed, not added: $app"
      continue
    fi
    if grep -Fqx -- "$app" <<<"$current"; then
      log_skip "$(basename "$app" .app)"
      continue
    fi
    hidden=false
    [[ $flag == hidden ]] && hidden=true
    if is_dry_run; then
      log_dry "open $(basename "$app" .app) at login${flag:+ ($flag)}"
    elif add_login_item "$app" "$hidden" >/dev/null; then
      log_success "$(basename "$app" .app) opens at login"
    else
      log_error "Couldn't add $(basename "$app" .app) to login items"
    fi
  done < <(read_manifest "$MANIFEST")

  module_finish
}

main "$@"
