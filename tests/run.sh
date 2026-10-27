#!/usr/bin/env bash
# run.sh — Lint and test everything without touching the real machine.
#   tests/run.sh                      # stock /bin/bash 3.2
#   TEST_BASH=/opt/homebrew/bin/bash tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."
status=0

echo "syntax (bash -n)"
for f in install.sh setup.sh capture.sh scripts/*.sh tests/*.sh; do
  /bin/bash -n "$f" || { echo "  ✗ $f"; status=1; }
done

if command -v shellcheck >/dev/null; then
  echo "shellcheck"
  shellcheck -x -S warning install.sh setup.sh capture.sh scripts/*.sh || status=1
else
  echo "shellcheck not installed; skipping lint"
fi

for t in tests/test_*.sh; do
  echo
  "${TEST_BASH:-/bin/bash}" "$t" || status=1
done
exit $status
