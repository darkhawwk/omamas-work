#!/usr/bin/env bash
# scripts/drift-check.sh (against a fake setup.sh with canned output) and
# 70-drift-check.sh (launchctl is a shim; plists are real and linted).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
D=scripts/drift-check.sh
M=scripts/70-drift-check.sh

git_q() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false "$@" -q; }

# new_mac SCENARIO(in-sync|drifted|locked)
new_mac() {
  new_sandbox
  SHIMS="$SANDBOX/shims"
  mkdir -p "$SHIMS" "$SANDBOX/repo"
  printf 'weekday 1\nhour 10\nminute 0\nskip login-items\n' >"$CFG/drift-check.conf"
  git_q init "$SANDBOX/repo" && (cd "$SANDBOX/repo" && echo a >a && git add a && git_q commit -m a)
  cat >"$SANDBOX/fake-setup" <<SH
#!/bin/bash
echo "\$*" >"$SANDBOX/setup-args"
case "$1" in
  locked) echo "[ERROR] Another Omamas run is in progress (pid 1)."; exit 1 ;;
  in-sync) printf '%s\n' "[SUCCESS] dock: 0 pending, 1 unchanged" "  dock                 ok   0s" "[INFO]    Log: ~/.local/state/omamas/logs/x.log" ;;
  drifted) printf '%s\n' "[SUCCESS] dock: 2 pending, 0 unchanged" \
    "[WARN]    Drift: installed but not in Brewfile → htop wget " \
    "[ERROR]   security: 1 pending, 1 unchanged, 1 failed" "  dock                 ok   0s" \
    "  security             FAILED   1s" "[INFO]    Log: ~/.local/state/omamas/logs/x.log"; exit 1 ;;
esac
SH
  # Real osascript passes trailing arguments to "on run argv": title, message.
  printf '#!/bin/bash\necho "${@: -1}" >>"%s/notified"\necho "$*" >>"%s/osascript.log"\n' "$SANDBOX" "$SANDBOX" >"$SHIMS/osascript"
  chmod +x "$SANDBOX/fake-setup" "$SHIMS/osascript"
  export EXTRA_ENV="PATH=$SHIMS:$PATH OMAMAS_DRIFT_SETUP=$SANDBOX/fake-setup OMAMAS_DRIFT_REPO=$SANDBOX/repo"
}
REPORT() { cat "$FAKE_HOME/.local/state/omamas/drift/latest.txt"; }

echo "drift-check: in sync"
new_mac in-sync
omamas $D
check "exits 0" rc_is 0
check "runs a dry run, skipping configured modules" grep -qx -- "--dry-run --skip login-items" "$SANDBOX/setup-args"
check "says it's in sync" has_output "In sync with configs/"
check "stays quiet" test ! -e "$SANDBOX/notified"
check "writes a report" grep -q "In sync: nothing differs" <<<"$(REPORT)"

echo "drift-check: drifted"
new_mac drifted
echo b >"$SANDBOX/repo/b"
omamas $D
check "exits 0 (it's a report, not a failure)" rc_is 0
check "lists modules with pending changes" grep -qx "Pending changes: dock (2), security (1)" <<<"$(REPORT)"
check "lists failed modules" grep -qx "Failed: security" <<<"$(REPORT)"
check "lists apps not in the Brewfile" grep -qx "Installed but not in Brewfile: htop wget" <<<"$(REPORT)"
check "notices uncommitted repo changes" grep -qx "Omamas repo: 1 uncommitted changes" <<<"$(REPORT)"
check "points at the full log" grep -q "Details: ~/.local/state/omamas/logs/x.log" <<<"$(REPORT)"
check "notifies once" test "$(wc -l <"$SANDBOX/notified" | tr -d ' ')" = 1
check "notification names the first issue and the rest" grep -q 'Pending changes: dock (2), security (1) (+3 more)' "$SANDBOX/notified"
check "message travels as an argument, not script text" bash -c "grep -q 'on run argv' '$SANDBOX/osascript.log'"
omamas $D --no-notify
check "--no-notify stays quiet" test "$(wc -l <"$SANDBOX/notified" | tr -d ' ')" = 1

echo "drift-check: setup already running"
new_mac locked
omamas $D
check "skips quietly" has_output "skipping this check"
check "no notification" test ! -e "$SANDBOX/notified"

# ── 70-drift-check ────────────────────────────────────────────────────────────
new_agent() {
  new_mac in-sync
  cat >"$SHIMS/launchctl" <<SH
#!/bin/bash
echo "\$*" >>"$SANDBOX/launchctl.log"
case "\$1" in
  print) [[ -e "$SANDBOX/loaded" ]] ;;
  bootstrap) touch "$SANDBOX/loaded" ;;
  bootout) rm -f "$SANDBOX/loaded" ;;
esac
SH
  chmod +x "$SHIMS/launchctl"
}
PLIST() { echo "$FAKE_HOME/Library/LaunchAgents/com.omamas.drift-check.plist"; }

echo "70-drift-check"
new_agent
omamas $M --dry-run
check "dry run reports the schedule" has_output "schedule the weekly drift check (weekday 1, 10:00)"
check "dry run writes nothing" test ! -e "$(PLIST)"
omamas $M
check "exits 0" rc_is 0
check "writes a valid plist" plutil -lint -s "$(PLIST)"
check "runs drift-check.sh from this repo" grep -q "$REPO/scripts/drift-check.sh" "$(PLIST)"
check "uses the configured schedule" test "$(plutil -extract StartCalendarInterval.Hour raw "$(PLIST)")" = 10
check "loads it" test -e "$SANDBOX/loaded"
omamas $M
check "second run changes nothing" has_output "0 changed, 1 unchanged"
printf 'weekday 5\nhour 18\nminute 30\n' >"$CFG/drift-check.conf"
omamas $M
check "reschedules when the config changes" test "$(plutil -extract StartCalendarInterval.Weekday raw "$(PLIST)")" = 5
check "reloads it" test "$(grep -c '^bootstrap' "$SANDBOX/launchctl.log")" = 2
printf 'hour 25\n' >"$CFG/drift-check.conf"
omamas $M
check "rejects an invalid hour" has_output "hour must be 0–23, not '25'"
rm "$CFG/drift-check.conf"
omamas $M
check "removing the config removes the agent" test ! -e "$(PLIST)" -a ! -e "$SANDBOX/loaded"
omamas $M
check "then stays removed" has_output "No drift-check.conf; no agent"

finish
