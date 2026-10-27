#!/usr/bin/env bash
# 64-default-apps.sh — Set default apps from configs/macos/default-apps.conf.
#
#   <bundle-id>  <url-scheme>                  e.g. com.brave.Browser  https
#   <bundle-id>  <uniform-type-id>  <role>     e.g. md.obsidian  net.daringfireball.markdown  all
#
# Each handler is read first (`duti -d`) and only set when it differs. macOS
# asks you to confirm a new default web browser; until you do, the old one
# stays, and this module leaves a follow-up rather than reporting success.
#
# Usage: scripts/64-default-apps.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/macos/default-apps.conf"

lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

# Bundle id currently handling TARGET (empty if none).
handler_for() { duti -d "$1" 2>/dev/null | head -n1 || true; }

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

  local id target role have unconfirmed=""
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
    if ! duti -s "$id" "$target" ${role:+"$role"} 2>/dev/null; then
      log_error "Couldn't set $target → $id (is the app installed?)"
      continue
    fi
    if [[ $(lower "$(handler_for "$target")") == "$(lower "$id")" ]]; then
      log_success "$target → $id (was: ${have:-none})"
    else
      log_warn "$target: macOS is asking you to confirm $id"
      unconfirmed+="$target "
    fi
  done < <(read_manifest "$MANIFEST")

  if [[ -n $unconfirmed ]]; then
    add_note "Confirm the macOS dialog(s) for ${unconfirmed% }, then: ./setup.sh --only default-apps"
  fi
  module_finish
}

main "$@"
