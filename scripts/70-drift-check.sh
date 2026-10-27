#!/usr/bin/env bash
# 70-drift-check.sh — Schedule scripts/drift-check.sh as a weekly LaunchAgent.
#
# Builds ~/Library/LaunchAgents/com.omamas.drift-check.plist from
# configs/drift-check.conf (weekday, hour, minute) and loads it. The file is
# rewritten and reloaded only when its content changes, e.g. after editing the
# schedule or moving the repo. Delete drift-check.conf to remove the agent.
#
# Usage: scripts/70-drift-check.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

LABEL=com.omamas.drift-check
CONF="$OMAMAS_CONFIG_DIR/drift-check.conf"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
STAGED=""

cleanup() { [[ -z $STAGED ]] || rm -f "$STAGED"; }

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }

setting() {
  local key value
  while read -r key value; do
    [[ $key == "$1" ]] && { printf '%s' "$value"; return 0; }
  done < <(read_manifest "$CONF")
  printf '%s' "$2"
}

# in_range VALUE MIN MAX
in_range() { [[ $1 =~ ^[0-9]+$ ]] && (($1 >= $2 && $1 <= $3)); }

render_plist() {
  local weekday=$1 hour=$2 minute=$3 log_dir="$OMAMAS_STATE_DIR/drift"
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$(xml_escape "$OMAMAS_ROOT/scripts/drift-check.sh")</string>
	</array>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Weekday</key>
		<integer>$weekday</integer>
		<key>Hour</key>
		<integer>$hour</integer>
		<key>Minute</key>
		<integer>$minute</integer>
	</dict>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
	</dict>
	<key>StandardOutPath</key>
	<string>$(xml_escape "$log_dir/agent.log")</string>
	<key>StandardErrorPath</key>
	<string>$(xml_escape "$log_dir/agent.log")</string>
	<key>ProcessType</key>
	<string>Background</string>
</dict>
</plist>
PLIST
}

is_loaded() { launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; }

remove_agent() {
  if is_dry_run; then
    log_dry "remove the drift-check LaunchAgent (no drift-check.conf)"
    return 0
  fi
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  if rm -f "$PLIST"; then
    log_success "Removed the drift-check LaunchAgent"
  else
    log_error "Couldn't remove $(tildify "$PLIST")"
  fi
}

main() {
  module_start "$@"
  require_macos

  if [[ ! -f $CONF ]]; then
    if [[ -e $PLIST ]]; then remove_agent; else log_skip "No drift-check.conf; no agent"; fi
    module_finish
    return 0
  fi

  local weekday hour minute
  weekday=$(setting weekday 1)
  hour=$(setting hour 10)
  minute=$(setting minute 0)
  in_range "$weekday" 0 7 || die "drift-check.conf: weekday must be 0–7, not '$weekday'"
  in_range "$hour" 0 23 || die "drift-check.conf: hour must be 0–23, not '$hour'"
  in_range "$minute" 0 59 || die "drift-check.conf: minute must be 0–59, not '$minute'"

  STAGED=$(mktemp -t omamas-drift-plist)
  add_exit_hook cleanup
  render_plist "$weekday" "$hour" "$minute" >"$STAGED"
  plutil -lint -s "$STAGED" || die "Generated an invalid LaunchAgent plist"

  if [[ -f $PLIST ]] && cmp -s "$STAGED" "$PLIST" && is_loaded; then
    log_skip "Weekly drift check scheduled (weekday $weekday, $(printf '%02d:%02d' "$hour" "$minute"))"
    module_finish
    return 0
  fi

  if is_dry_run; then
    log_dry "schedule the weekly drift check (weekday $weekday, $(printf '%02d:%02d' "$hour" "$minute"))"
    module_finish
    return 0
  fi

  mkdir -p "$(dirname "$PLIST")" "$OMAMAS_STATE_DIR/drift"
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  if cp "$STAGED" "$PLIST" && launchctl bootstrap "$DOMAIN" "$PLIST"; then
    log_success "Weekly drift check scheduled (weekday $weekday, $(printf '%02d:%02d' "$hour" "$minute"))"
  else
    log_error "Couldn't load $(tildify "$PLIST")"
  fi
  module_finish
}

main "$@"
