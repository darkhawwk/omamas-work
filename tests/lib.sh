#!/usr/bin/env bash
# lib.sh — Minimal test harness. Every test runs against a throwaway sandbox:
# a fake $HOME, a fixture configs/ dir and its own state dir, so nothing on the
# real machine is read from or written to (macOS defaults tests use plist
# *paths* as domains for the same reason).

set -uo pipefail

REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BASH="${TEST_BASH:-/bin/bash}" # stock macOS bash 3.2 by default
PASSED=0
FAILED=0

# Create a fresh sandbox and point SANDBOX/FAKE_HOME/CFG at it.
new_sandbox() {
  [[ -z ${SANDBOX:-} ]] || rm -rf "$SANDBOX"
  SANDBOX=$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/omamas-test.XXXXXX")" && pwd)
  FAKE_HOME="$SANDBOX/home"
  CFG="$SANDBOX/configs"
  mkdir -p "$FAKE_HOME" "$CFG/home"
}

# Run an Omamas script inside the sandbox; captures OUT and RC.
omamas() {
  OUT=$(env -u XDG_STATE_HOME -u OMAMAS_STATE_DIR -u OMAMAS_RUN_ID \
    HOME="$FAKE_HOME" OMAMAS_CONFIG_DIR="$CFG" OMAMAS_COLOR=0 OMAMAS_SKIP_NETWORK_CHECK=1 OMAMAS_TEST_MODE=1 \
    OMAMAS_FONT_DIR="$FAKE_HOME/Library/Fonts" ${EXTRA_ENV:-} \
    "$TEST_BASH" "$REPO/$1" "${@:2}" 2>&1)
  RC=$?
}

pass() { PASSED=$((PASSED + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗ %s\033[0m\n' "$1"
  [[ -z ${OUT:-} ]] || printf '%s\n' "$OUT" | sed 's/^/      │ /'
}

check() { # check "description" <test command...>
  local desc=$1
  shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}

is_link_to() { [[ -L $1 && $(readlink "$1") == "$2" ]]; }
has_output() { grep -Fq -- "$1" <<<"$OUT"; }
lacks_output() { ! grep -Fq -- "$1" <<<"$OUT"; }
rc_is() { [[ $RC -eq $1 ]]; }
content_is() { [[ -f $1 && $(cat "$1") == "$2" ]]; }
# section_has FILE "## Heading" TEXT — TEXT appears under that Markdown heading.
section_has() {
  awk -v h="$2" 'index($0, h) == 1 { on = 1; next } /^## / { on = 0 } on' "$1" | grep -Fq -- "$3"
}
backups_dir() { echo "$FAKE_HOME/.local/state/omamas/backups"; }

finish() {
  rm -rf "${SANDBOX:-}"
  printf '  %d passed, %d failed\n' "$PASSED" "$FAILED"
  ((FAILED == 0))
}
