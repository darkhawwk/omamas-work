#!/usr/bin/env bash
# Behavior of 15-1password.sh. brew and open are shims on PATH and the app path
# points into the sandbox, so nothing is installed or launched.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/15-1password.sh

# new_mac STATE(missing|manual|brew) [INSTALL(ok|fail)]
new_mac() {
  new_sandbox
  SHIMS="$SANDBOX/shims"
  APP="$SANDBOX/Applications/1Password.app"
  mkdir -p "$SHIMS" "$SANDBOX/Applications"
  case $1 in
    manual) mkdir -p "$APP" ;;
    brew) mkdir -p "$APP" && touch "$SANDBOX/brew-managed" ;;
  esac
  echo "${2:-ok}" >"$SANDBOX/install-result"

  cat >"$SHIMS/brew" <<SH
#!/bin/bash
echo "\$*" >>"$SANDBOX/brew.log"
case "\$1" in
  list) [[ -e "$SANDBOX/brew-managed" ]] ;;
  install)
    [[ \$(cat "$SANDBOX/install-result") == ok ]] || exit 1
    mkdir -p "$APP" && touch "$SANDBOX/brew-managed" ;;
esac
SH
  cat >"$SHIMS/open" <<SH
#!/bin/bash
echo "\$*" >>"$SANDBOX/open.log"
# Like macOS's first-launch prompt for a downloaded app: nobody answers.
[[ -e "$SANDBOX/open-hangs" ]] && sleep 30
exit 0
SH
  chmod +x "$SHIMS"/*
  export EXTRA_ENV="PATH=$SHIMS:$PATH OMAMAS_1PASSWORD_APP=$APP"
}

installs() { grep -c '^install' "$SANDBOX/brew.log" 2>/dev/null || true; }
# `open` runs detached, so give it a moment to record the call.
opened() { local i; for i in 1 2 3 4 5 6 7 8 9 10; do grep -Fqx "$APP" "$SANDBOX/open.log" 2>/dev/null && return 0; sleep 0.3; done; return 1; }

echo "1password: missing"
new_mac missing
omamas $M --dry-run
check "dry run reports the install" has_output "1 pending"
check "dry run installs nothing" test "$(installs)" = 0
omamas $M
check "exits 0" rc_is 0
check "installs the cask" grep -Fqx "install --cask 1password" "$SANDBOX/brew.log"
check "opens the app for sign-in" opened
check "says setup continues" has_output "Setup continues meanwhile"
check "leaves a follow-up about the SSH agent" has_output "turn on its SSH agent"
omamas $M
check "second run changes nothing" has_output "0 changed, 1 unchanged"
check "opens the app only once" test "$(wc -l <"$SANDBOX/open.log" | tr -d ' ')" = 1

echo "1password: first-launch prompt nobody answers"
new_mac missing
touch "$SANDBOX/open-hangs"
start=$SECONDS
omamas $M
check "doesn't wait for the prompt" test $((SECONDS - start)) -lt 10
check "still opens the app" opened
check "exits 0" rc_is 0

echo "1password: installed by hand"
new_mac manual
omamas $M
check "exits 0" rc_is 0
check "adopts instead of reinstalling" grep -Fqx "install --cask --adopt 1password" "$SANDBOX/brew.log"
check "does not open the app" test ! -e "$SANDBOX/open.log"
omamas $M
check "then converges" has_output "0 changed, 1 unchanged"

echo "1password: hand install that can't be adopted"
new_mac manual fail
omamas $M
check "exits non-zero" rc_is 1
check "explains how to fix it" has_output "Check for Updates"
check "leaves the app alone" test -d "$APP"

echo "1password: already managed by Homebrew"
new_mac brew
omamas $M
check "skips" has_output "1Password installed (Homebrew)"
check "runs no install" test "$(installs)" = 0

echo "1password: install fails"
new_mac missing fail
omamas $M
check "exits non-zero" rc_is 1
check "does not open anything" test ! -e "$SANDBOX/open.log"

finish
