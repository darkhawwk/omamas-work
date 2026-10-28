#!/usr/bin/env bash
# 17-security.sh — Apply the baseline in configs/macos/security.conf.
#
#   firewall   on|off   macOS application firewall
#   stealth    on|off   ignore pings and probes to closed ports
#   filevault  check    report disk encryption; turning it on needs you
#                       (and produces a recovery key), so it's never automated
#
# Numbered before 20-packages on purpose: it's the last module that needs
# sudo, and setup.sh drops the sudo ticket after packages, so the steps that
# follow (repo clones, runtime downloads, secrets) run without root access.
#
# Usage: scripts/17-security.sh [--dry-run] [--help]

# omamas: requires-sudo

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/macos/security.conf"
FW=$(test_override OMAMAS_SOCKETFILTERFW /usr/libexec/ApplicationFirewall/socketfilterfw)

# on|off from socketfilterfw's wording ("Firewall is enabled. (State = 1)",
# "Firewall stealth mode is on").
fw_state() {
  # Careful: "disabled" contains "enabled", so match whole phrases only.
  if "$FW" "$1" 2>/dev/null | grep -Eqi 'is enabled|State = [12]|mode is on|mode enabled'; then echo on; else echo off; fi
}

# set_fw LABEL GET_FLAG SET_FLAG WANT
set_fw() {
  local label=$1 get=$2 set=$3 want=$4 have
  case $want in on | off) ;; *) log_error "$label must be on or off, not '$want'"; return 0 ;; esac
  have=$(fw_state "$get")
  if [[ $have == "$want" ]]; then
    log_skip "$label $have"
    return 0
  fi
  if is_dry_run; then
    log_dry "$label: $have → $want"
    return 0
  fi
  require_sudo
  if sudo "$FW" "$set" "$want" >/dev/null && [[ $(fw_state "$get") == "$want" ]]; then
    log_success "$label $want (was: $have)"
  else
    log_error "Couldn't turn $label $want"
  fi
}

check_filevault() {
  local status
  status=$(fdesetup status 2>/dev/null | head -n1 || true)
  case $status in
    "FileVault is On."*) log_skip "FileVault on" ;;
    "FileVault is Off."*)
      log_warn "FileVault is off: this Mac's disk isn't encrypted"
      add_note "Turn on FileVault: System Settings → Privacy & Security → FileVault (save the recovery key in 1Password)."
      ;;
    *) log_info "FileVault: ${status:-unknown}" ;;
  esac
}

main() {
  module_start "$@"
  require_macos
  if [[ ! -f $MANIFEST ]]; then
    log_skip "No $(tildify "$MANIFEST")"
    module_finish
    return 0
  fi

  local key value
  while read -r key value; do
    case $key in
      firewall) set_fw firewall --getglobalstate --setglobalstate "$value" ;;
      stealth) set_fw "stealth mode" --getstealthmode --setstealthmode "$value" ;;
      filevault) check_filevault ;;
      *) log_error "Unknown setting '$key' in $(tildify "$MANIFEST")" ;;
    esac
  done < <(read_manifest "$MANIFEST")

  module_finish
}

main "$@"
