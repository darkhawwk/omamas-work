#!/usr/bin/env bash
# Behavior of 60-macos-defaults.sh. Domains are plist *paths* inside the
# sandbox, so the real user preferences are never read or written.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/60-macos-defaults.sh
export EXTRA_ENV="OMAMAS_NO_RESTART=1"

echo "defaults: apply + idempotency"
new_sandbox
D="$SANDBOX/prefs/com.omamas.test"
mkdir -p "$CFG/macos" "$SANDBOX/prefs"
cat >"$CFG/macos/defaults.conf" <<CONF
# comment lines and blanks are ignored

$D  flag    -bool    YES
$D  count   -int     42
$D  ratio   -float   0.5
$D  where   -string  ~/Pictures/Shots
CONF
omamas $M
check "exits 0" rc_is 0
check "reports 4 changed" has_output "4 changed, 0 unchanged"
check "bool stored as boolean true" test "$(defaults read "$D" flag)" = 1
check "~ expanded in string values" test "$(defaults read "$D" where)" = "$FAKE_HOME/Pictures/Shots"
omamas $M
check "second run changes nothing" has_output "0 changed, 4 unchanged"

echo "defaults: type drift is corrected"
defaults write "$D" flag -string 1 # same printed value, wrong type
omamas $M
check "rewrites value of the wrong type" has_output "1 changed, 3 unchanged"
check "type restored to boolean" test "$(defaults read-type "$D" flag)" = "Type is boolean"
check "logs the value it replaced" has_output "flag = true (was: 1 (string))"

echo "defaults: dry run"
defaults write "$D" count -int 7
omamas $M --dry-run
check "reports pending change" has_output "1 pending"
check "does not write" test "$(defaults read "$D" count)" = 7
check "shows the current value" has_output "currently: 7 (integer)"

echo "defaults: invalid entries"
cat >>"$CFG/macos/defaults.conf" <<CONF
$D  list    -array   a b
$D  flag2   -bool    maybe
CONF
omamas $M
check "exits non-zero" rc_is 1
check "rejects collection types" has_output "unsupported type '-array'"
check "rejects bad booleans" has_output "'maybe' is not a valid -bool"
check "still applies the valid entries" test "$(defaults read "$D" count)" = 42

finish
