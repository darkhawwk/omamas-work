#!/usr/bin/env bash
# 60-macos-defaults.sh — Apply system/UI preferences from configs/macos/defaults.conf.
#
# Manifest format, one setting per line:   <domain> <key> <type> <value...>
#   com.apple.dock       autohide          -bool    true
#   NSGlobalDomain       KeyRepeat         -int     2
#   com.apple.screencapture location       -string  ~/Pictures/Screenshots
#
# Supported types: -bool -int -float -string. Each setting is read back first
# (value *and* type) and only written when it differs, so re-runs are no-ops.
# Collection types (-array, -dict, -*-add) cannot be compared reliably and are
# rejected; put those in a dedicated module. Affected apps (Dock, Finder, ...)
# are restarted once at the end, and only if something they own changed.
# Set OMAMAS_NO_RESTART=1 to leave running apps alone (changes then apply on
# next launch/login) — handy when reconciling a machine you're working on.
#
# Usage: scripts/60-macos-defaults.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/macos/defaults.conf"
RESTART=" " # space-delimited set of processes to restart (no assoc arrays in bash 3.2)
SETTINGS_CLOSED=0

# Map a defaults domain to the process that must restart to pick it up.
process_for_domain() {
  case $1 in
    com.apple.dock) echo Dock ;;
    com.apple.finder) echo Finder ;;
    com.apple.SystemUIServer | com.apple.screencapture | com.apple.menuextra.*) echo SystemUIServer ;;
    NSGlobalDomain | -g | -globalDomain) echo "@logout" ;;
  esac
}

# Normalize a manifest value into the form `defaults read` prints.
normalize() {
  local type=$1 value=$2
  case $type in
    -bool | -boolean)
      case $(printf '%s' "$value" | tr '[:upper:]' '[:lower:]') in
        true | yes | 1) echo 1 ;;
        false | no | 0) echo 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) printf '%s\n' "$value" ;;
  esac
}

# `defaults read-type` vocabulary for each supported write flag.
type_name() {
  case $1 in
    -bool | -boolean) echo boolean ;;
    -int | -integer) echo integer ;;
    -float) echo float ;;
    -string) echo string ;;
    *) return 1 ;;
  esac
}

is_current() {
  local domain=$1 key=$2 type=$3 want=$4 have have_type
  have=$(defaults read "$domain" "$key" 2>/dev/null) || return 1
  have_type=$(defaults read-type "$domain" "$key" 2>/dev/null) || return 1
  [[ $have_type == "Type is $(type_name "$type")" ]] || return 1
  if [[ $type == -float ]]; then
    # Relative tolerance: macOS often stores single-precision values, so 0.1
    # reads back as 0.10000000149011612.
    awk -v a="$have" -v b="$want" 'BEGIN { d = a - b; if (d < 0) d = -d; m = (b < 0 ? -b : b); if (m < 1) m = 1; exit !(d <= 1e-6 * m) }'
  else
    [[ $have == "$want" ]]
  fi
}

# Current value and type for change logs, e.g. "2 (integer)" or "unset", so a
# setting that flips on every run shows what macOS wrote back.
describe_current() {
  local v t
  v=$(defaults read "$1" "$2" 2>/dev/null) || {
    echo unset
    return 0
  }
  t=$(defaults read-type "$1" "$2" 2>/dev/null) || t=""
  printf '%s (%s)' "${v%%$'\n'*}" "${t#Type is }"
}

# An open System Settings window can overwrite freshly written values, so close
# it lazily — right before the first actual write.
quit_system_settings() {
  ((SETTINGS_CLOSED == 0)) || return 0
  SETTINGS_CLOSED=1
  [[ ${OMAMAS_NO_RESTART:-0} != 1 ]] || return 0
  local app
  for app in "System Settings" "System Preferences"; do
    if pgrep -xq "$app"; then
      run osascript -e "quit app \"$app\"" || true
    fi
  done
}

DOMAIN='^(NSGlobalDomain|[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+)+)$'

main() {
  module_start "$@"
  require_macos

  if [[ ! -f $MANIFEST ]]; then
    log_skip "No manifest at $(tildify "$MANIFEST")"
    module_finish
    return 0
  fi

  local domain key type value want proc was
  while read -r domain key type value; do
    value=${value/#\~/$HOME}
    domain=${domain/#\~/$HOME}

    # Only preference domains, never file paths: given a path, `defaults
    # write` replaces that file with a plist. The tests write plist paths
    # inside their sandbox, so test mode allows them.
    if [[ ! $domain =~ $DOMAIN && ${OMAMAS_TEST_MODE:-0} != 1 ]]; then
      log_error "$domain: not a preference domain (like com.apple.dock or NSGlobalDomain)"
      continue
    fi

    if ! type_name "$type" >/dev/null; then
      log_error "$domain $key: unsupported type '$type' (use -bool, -int, -float or -string)"
      continue
    fi
    if ! want=$(normalize "$type" "$value"); then
      log_error "$domain $key: '$value' is not a valid $type"
      continue
    fi

    if is_current "$domain" "$key" "$type" "$want"; then
      log_skip "$domain $key = $value"
      continue
    fi

    # Write booleans canonically; everything else verbatim.
    if [[ $type == -bool || $type == -boolean ]]; then
      if [[ $want == 1 ]]; then value=true; else value=false; fi
    fi
    was=$(describe_current "$domain" "$key")
    quit_system_settings
    if run defaults write "$domain" "$key" "$type" "$value"; then
      if is_dry_run; then
        log_info "  currently: $was"
      else
        log_success "$domain $key = $value (was: $was)"
      fi
      proc=$(process_for_domain "$domain")
      [[ -z $proc || $RESTART == *" $proc "* ]] || RESTART="$RESTART$proc "
    else
      log_error "Failed to write $domain $key"
    fi
  done < <(read_manifest "$MANIFEST")

  for proc in $RESTART; do
    if [[ $proc == "@logout" ]]; then
      add_note "Some global (NSGlobalDomain) preferences take effect after logging out."
    elif [[ ${OMAMAS_NO_RESTART:-0} == 1 ]]; then
      add_note "Restart $proc (or log out) to apply its new preferences."
    elif pgrep -xq "$proc"; then
      run killall "$proc" && log_info "Restarted $proc"
    fi
  done

  module_finish
}

main "$@"
