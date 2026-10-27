#!/usr/bin/env bash
# Behavior of the smaller modules: directories, fonts, and the template contract.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "directories"
new_sandbox
cat >"$CFG/directories.conf" <<'CONF'
~/Work
~/.ssh   700
CONF
omamas scripts/30-directories.sh
check "exits 0" rc_is 0
check "creates directories" test -d "$FAKE_HOME/Work" -a -d "$FAKE_HOME/.ssh"
check "applies mode" test "$(stat -f '%Lp' "$FAKE_HOME/.ssh")" = 700
chmod 755 "$FAKE_HOME/.ssh"
omamas scripts/30-directories.sh
check "corrects mode drift only" has_output "1 changed, 1 unchanged"
touch "$FAKE_HOME/Blocked" && echo "~/Blocked" >>"$CFG/directories.conf"
omamas scripts/30-directories.sh
check "refuses to replace a file" has_output "exists but is not a directory"
check "file left intact" test -f "$FAKE_HOME/Blocked"

echo "fonts"
new_sandbox
mkdir -p "$CFG/fonts"
printf 'font-v1' >"$CFG/fonts/Mono.ttf"
printf 'readme' >"$CFG/fonts/README.txt"
omamas scripts/50-fonts.sh
check "installs font files" content_is "$FAKE_HOME/Library/Fonts/Mono.ttf" font-v1
check "ignores non-font files" test ! -e "$FAKE_HOME/Library/Fonts/README.txt"
omamas scripts/50-fonts.sh
check "identical font skipped" has_output "0 changed, 1 unchanged"
printf 'font-v2' >"$CFG/fonts/Mono.ttf"
omamas scripts/50-fonts.sh
check "changed font replaced" content_is "$FAKE_HOME/Library/Fonts/Mono.ttf" font-v2
check "old font backed up" test -n "$(find "$(backups_dir)" -name Mono.ttf)"

echo "module contract"
new_sandbox
for m in "$REPO"/scripts/[0-9][0-9]-*.sh; do
  omamas "scripts/${m##*/}" --help
  check "${m##*/} --help works standalone" rc_is 0
  check "${m##*/} is executable" test -x "$m"
done
omamas scripts/40-dotfiles.sh --bogus
check "unknown flag rejected" rc_is 1

finish
