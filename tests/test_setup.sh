#!/usr/bin/env bash
# Orchestrator behavior, always in --dry-run inside the sandbox.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "setup.sh"
new_sandbox
echo x >"$CFG/home/.zshrc"
omamas setup.sh --list
check "--list prints modules in order" test "$(printf '%s\n' "$OUT" | cut -f1 | tr '\n' ' ')" = "computer-name sudo-touchid rosetta homebrew 1password security packages directories dotfiles repos runtimes secrets fonts macos-defaults dock default-apps login-items drift-check "
omamas setup.sh --only bogus
check "unknown module rejected" rc_is 1
omamas setup.sh --dry-run --only directories --only dotfiles
check "dry run exits 0" rc_is 0
check "runs selected modules" has_output "[2/2] dotfiles"
check "prints summary" has_output "Omamas finished"
check "changes nothing" test ! -e "$FAKE_HOME/.zshrc"
LOG="$FAKE_HOME/.local/state/omamas/logs/latest.log"
check "writes a log file" test -s "$LOG"
check "log is free of ANSI escapes" bash -c "! grep -q $'\033' '$LOG'"
check "releases its lock" test ! -d "$FAKE_HOME/.local/state/omamas/setup.lock"

echo "setup.sh: real run (modules that need no sudo)"
echo old >"$FAKE_HOME/.zshrc"
omamas setup.sh --only dotfiles
check "exits 0" rc_is 0
check "applies changes" is_link_to "$FAKE_HOME/.zshrc" "$CFG/home/.zshrc"
check "reports backup location" has_output "Backups: ~/.local/state/omamas/backups/"
check "does not ask for sudo" lacks_output "Administrator privileges"
omamas setup.sh --only dotfiles
check "re-run is a no-op" has_output "0 changed, 1 unchanged"

echo "setup.sh: sudo window"
# A sudo shim logs calls; the real sudo is never touched.
mkdir -p "$SANDBOX/shims"
printf '#!/bin/bash\necho "$*" >>"%s/sudo.log"\n' "$SANDBOX" >"$SANDBOX/shims/sudo"
chmod +x "$SANDBOX/shims/sudo"
OUT=$(PATH="$SANDBOX/shims:$PATH" HOME="$FAKE_HOME" OMAMAS_COLOR=0 "$TEST_BASH" -c '
  source "$1/scripts/utils.sh"
  require_sudo
  pid=$OMAMAS_SUDO_KEEPALIVE_PID
  end_sudo
  sleep 0.2
  kill -0 "$pid" 2>/dev/null && echo "keepalive still running"
  [[ -z ${OMAMAS_SUDO_KEEPALIVE_PID:-} ]] || echo "pid still exported"
  echo done' _ "$REPO" 2>&1)
check "end_sudo stops the keep-alive" has_output "done"
check "end_sudo leaves nothing running" lacks_output "still"
check "end_sudo drops the ticket" grep -qx -- -k "$SANDBOX/sudo.log"
last=$(grep -l '^# omamas: requires-sudo' "$REPO"/scripts/[0-9][0-9]-*.sh | tail -n1)
check "packages is the last module holding sudo" test "${last##*/}" = 20-packages.sh

echo "setup.sh: failing module"
mkdir -p "$CFG/home/.config/x" && echo x >"$CFG/home/.config/x/rc"
ln -s "$CFG/home/.config" "$FAKE_HOME/.config"
omamas setup.sh --only directories --only dotfiles
check "exits non-zero" rc_is 1
check "summary marks the failure" has_output "1 module(s) failed"
check "other modules still ran" has_output "directories          ok"

finish
