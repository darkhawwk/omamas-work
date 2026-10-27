#!/usr/bin/env bash
# 62-dock.sh — Make the Dock's pinned apps match configs/macos/dock.conf.
#
# While dock.conf exists, the Dock holds exactly its apps, in order, and no
# folders or stacks (a new Mac starts with Apple's apps and a Downloads stack).
# Apps that aren't installed are skipped. The Dock is rebuilt only when it
# differs, then restarted once (unless OMAMAS_NO_RESTART=1).
#
# Usage: scripts/62-dock.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/macos/dock.conf"

# Paths of items in one Dock section, in order ("file:///A%20B.app/" → "/A B.app").
dock_section() {
  dockutil --list 2>/dev/null | awk -F'\t' -v s="$1" '$3 == s { print $2 }' |
    /usr/bin/perl -pe 's#^file://##; s#/$##; s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg'
}

main() {
  module_start "$@"
  require_macos
  if [[ ! -f $MANIFEST ]]; then
    log_skip "No $(tildify "$MANIFEST"); Dock left alone"
    module_finish
    return 0
  fi
  ensure_brew_shellenv || true
  require_cmd dockutil "It's in the Brewfile; run scripts/20-packages.sh first."

  local app want=() current others
  while IFS= read -r app; do
    if [[ -d $app ]]; then
      want+=("$app")
    else
      log_warn "Not installed, left out of the Dock: $app"
    fi
  done < <(read_manifest "$MANIFEST")

  current=$(dock_section persistentApps)
  others=$(dock_section persistentOthers | grep -c . || true)
  if [[ $current == "$(printf '%s\n' ${want[@]+"${want[@]}"} | grep . || true)" ]] && ((others == 0)); then
    log_skip "Dock: ${#want[@]} apps, no folders"
    module_finish
    return 0
  fi

  if is_dry_run; then
    log_dry "set the Dock to ${#want[@]} apps and no folders (now $(grep -c . <<<"$current" || true) apps, $others folders)"
    module_finish
    return 0
  fi

  if [[ -n $current ]] || ((others > 0)); then
    dockutil --remove all --no-restart >/dev/null || { log_error "dockutil couldn't clear the Dock"; module_finish; }
  fi
  for app in ${want[@]+"${want[@]}"}; do
    dockutil --add "$app" --no-restart >/dev/null || log_error "dockutil couldn't add $app"
  done
  if [[ ${OMAMAS_NO_RESTART:-0} != 1 ]] && pgrep -xq Dock; then
    killall Dock || true
  fi
  log_success "Dock set to ${#want[@]} apps, no folders"
  module_finish
}

main "$@"
