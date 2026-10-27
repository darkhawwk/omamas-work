#!/usr/bin/env bash
# Behavior of 05-sudo-touchid.sh against a sandbox PAM directory that holds a
# verbatim copy of Apple's template. /etc/pam.d is never read or written.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/05-sudo-touchid.sh

template() {
  cat <<'PAM'
# sudo_local: local config file which survives system update and is included for sudo
# uncomment following line to enable Touch ID for sudo
#auth       sufficient     pam_tid.so
PAM
}

new_pam_sandbox() {
  new_sandbox
  PAM="$SANDBOX/pam.d"
  mkdir -p "$PAM"
  export EXTRA_ENV="OMAMAS_PAM_DIR=$PAM"
}

echo "sudo-touchid: from Apple's template"
new_pam_sandbox
template >"$PAM/sudo_local.template"
omamas $M
check "exits 0" rc_is 0
check "creates sudo_local with pam_tid enabled" grep -Eq '^auth +sufficient +pam_tid\.so$' "$PAM/sudo_local"
check "keeps Apple's header comments" test "$(grep -c '^# ' "$PAM/sudo_local")" = 2
check "has no commented pam_tid left" bash -c "! grep -q '^#auth' '$PAM/sudo_local'"
check "uses Apple's mode (0444)" test "$(stat -f '%Lp' "$PAM/sudo_local")" = 444
template >"$SANDBOX/original"
check "leaves the template untouched" cmp -s "$PAM/sudo_local.template" "$SANDBOX/original"
check "leaves no staging file behind" test ! -e "$PAM/sudo_local.omamas-new"
omamas $M
check "second run changes nothing" has_output "0 changed, 1 unchanged"

echo "sudo-touchid: existing custom sudo_local"
new_pam_sandbox
template >"$PAM/sudo_local.template"
echo 'auth       optional       /opt/homebrew/lib/pam/pam_reattach.so' >"$PAM/sudo_local"
omamas $M
check "exits 0" rc_is 0
check "keeps the existing line first" test "$(head -n1 "$PAM/sudo_local")" = 'auth       optional       /opt/homebrew/lib/pam/pam_reattach.so'
check "appends pam_tid after it" test "$(tail -n1 "$PAM/sudo_local")" = 'auth       sufficient     pam_tid.so'
check "backs up the original as a copy" test -n "$(find "$(backups_dir)" -name sudo_local)"

echo "sudo-touchid: existing sudo_local still commented"
new_pam_sandbox
template >"$PAM/sudo_local"
omamas $M
check "uncomments in place (no duplicate line)" test "$(grep -c pam_tid "$PAM/sudo_local")" = 1

echo "sudo-touchid: dry run and unsupported systems"
new_pam_sandbox
template >"$PAM/sudo_local.template"
omamas $M --dry-run
check "dry run reports the change" has_output "1 pending"
check "dry run writes nothing" test ! -e "$PAM/sudo_local"
rm "$PAM/sudo_local.template"
omamas $M
check "no template: exits 0" rc_is 0
check "no template: explains why" has_output "requires macOS 14+"

finish
