#!/usr/bin/env bash
# 05-sudo-touchid.sh — Let sudo authenticate with Touch ID.
#
# Creates /etc/pam.d/sudo_local from Apple's sudo_local.template with the
# pam_tid.so line uncommented. sudo_local (macOS 14+) is included by
# /etc/pam.d/sudo and survives OS updates, unlike edits to sudo itself.
# Numbered first, so it runs right after setup.sh's one password prompt and
# every later sudo prompt (this run's and all future ones) accepts a fingerprint.
# The password stays as fallback: no enrolled finger, lid closed, SSH sessions.
#
# Only ever *adds* the pam_tid line. Any other lines in an existing sudo_local
# (e.g. pam_reattach for tmux) are kept, and the old file is backed up.
# Undo with: sudo rm /etc/pam.d/sudo_local
#
# Usage: scripts/05-sudo-touchid.sh [--dry-run] [--help]

# omamas: requires-sudo

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

PAM_DIR=$(test_override OMAMAS_PAM_DIR /etc/pam.d) # tests point this at a sandbox
TARGET="$PAM_DIR/sudo_local"
TEMPLATE="$PAM_DIR/sudo_local.template"
TID_ACTIVE='^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so'
TID_COMMENTED='^[[:space:]]*#[[:space:]]*(auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so.*)$'
TID_LINE='auth       sufficient     pam_tid.so'
STAGED=""

cleanup() { [[ -z $STAGED ]] || rm -f "$STAGED"; }

# Elevate only when the PAM directory requires it.
as_root() { if [[ -w $PAM_DIR ]]; then "$@"; else sudo "$@"; fi; }

# Print BASE with pam_tid enabled: uncomment Apple's line if present,
# otherwise append it (after any existing lines such as pam_reattach).
render() {
  if grep -Eq "$TID_COMMENTED" "$1"; then
    sed -E "s/$TID_COMMENTED/\1/" "$1"
  else
    cat "$1"
    printf '%s\n' "$TID_LINE"
  fi
}

# The staged file may differ from BASE only by enabling pam_tid. Anything else
# means render() misbehaved, and a broken PAM file can lock you out of sudo.
verify_staged() {
  local base=$1
  grep -Eq "$TID_ACTIVE" "$STAGED" || return 1
  diff <(grep -Ev 'pam_tid\.so' "$base") <(grep -Ev 'pam_tid\.so' "$STAGED") >/dev/null
}

main() {
  module_start "$@"
  require_macos

  if [[ -f $TARGET ]] && grep -Eq "$TID_ACTIVE" "$TARGET"; then
    log_skip "Touch ID already enabled for sudo"
    module_finish
    return 0
  fi

  local base
  if [[ -f $TARGET ]]; then
    base=$TARGET
  elif [[ -f $TEMPLATE ]]; then
    base=$TEMPLATE
  else
    log_warn "No $TEMPLATE (requires macOS 14+); leaving sudo unchanged"
    module_finish
    return 0
  fi

  STAGED=$(mktemp -t omamas-sudo_local)
  add_exit_hook cleanup
  render "$base" >"$STAGED"
  verify_staged "$base" || die "Refusing to write $TARGET: rendered file failed verification"

  if is_dry_run; then
    log_dry "enable Touch ID for sudo in $TARGET (from ${base##*/})"
    module_finish
    return 0
  fi

  [[ -w $PAM_DIR ]] || require_sudo
  if [[ -f $TARGET ]]; then
    backup_path --copy "$TARGET" || die "Could not back up $TARGET"
  fi

  # Stage beside the target, then rename: sudo never reads a half-written file.
  # `install` run as root also yields Apple's ownership (root:wheel, 0444).
  if as_root install -m 444 "$STAGED" "$TARGET.omamas-new" &&
    as_root mv -f "$TARGET.omamas-new" "$TARGET"; then
    log_success "Touch ID enabled for sudo ($TARGET)"
  else
    as_root rm -f "$TARGET.omamas-new" || true
    log_error "Could not write $TARGET"
  fi

  module_finish
}

main "$@"
