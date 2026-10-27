#!/usr/bin/env bash
# 02-computer-name.sh — Name this Mac from configs/macos/computer-name.conf.
#
# Sets all three names macOS keeps, each only if it differs:
#   ComputerName   friendly name (Finder, AirDrop, Sharing)   e.g. "Bizarro"
#   LocalHostName  Bonjour name, <name>.local                 e.g. "Bizarro"
#   HostName       what `hostname` and the shell prompt show  e.g. "Bizarro"
# The two network names are derived from the friendly one (letters, digits and
# hyphens only). If another Mac on the network already uses the name, macOS
# appends a number to the Bonjour name until one of them is renamed.
#
# Usage: scripts/02-computer-name.sh [--dry-run] [--help]

# omamas: requires-sudo

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/macos/computer-name.conf"

# "My Mac's Name" → "My-Mac-s-Name": what LocalHostName/HostName accept.
network_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9-' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//'
}

set_name() {
  local key=$1 want=$2 have
  have=$(scutil --get "$key" 2>/dev/null || true)
  if [[ $have == "$want" ]]; then
    log_skip "$key = $want"
    return 0
  fi
  if is_dry_run; then
    log_dry "$key: ${have:-unset} → $want"
  elif sudo scutil --set "$key" "$want"; then
    log_success "$key = $want (was: ${have:-unset})"
  else
    log_error "Could not set $key"
  fi
}

main() {
  module_start "$@"
  require_macos

  local name net
  name=$(read_manifest "$MANIFEST" | head -n1)
  if [[ -z $name ]]; then
    log_skip "No name in $(tildify "$MANIFEST")"
    module_finish
    return 0
  fi
  net=$(network_name "$name")
  [[ -n $net ]] || die "'$name' has no letters or digits to build a network name from"

  # Only ask for sudo when something actually has to change.
  if ! is_dry_run && {
    [[ $(scutil --get ComputerName 2>/dev/null) != "$name" ]] ||
      [[ $(scutil --get LocalHostName 2>/dev/null) != "$net" ]] ||
      [[ $(scutil --get HostName 2>/dev/null) != "$net" ]]
  }; then
    require_sudo
  fi

  set_name ComputerName "$name"
  set_name LocalHostName "$net"
  set_name HostName "$net"

  module_finish
}

main "$@"
