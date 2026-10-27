#!/usr/bin/env bash
# Behavior of 07-rosetta.sh. sysctl, arch, softwareupdate and sudo are replaced
# by shims on PATH, so nothing is installed and no password is needed.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/07-rosetta.sh

# new_machine ARM64(0|1) ROSETTA(installed|missing) [INSTALL(ok|fail)]
new_machine() {
  new_sandbox
  SHIMS="$SANDBOX/shims"
  mkdir -p "$SHIMS"
  echo "$1" >"$SANDBOX/arm64"
  [[ $2 == installed ]] && touch "$SANDBOX/rosetta"
  echo "${3:-ok}" >"$SANDBOX/install-result"

  cat >"$SHIMS/sysctl" <<SH
#!/bin/bash
cat "$SANDBOX/arm64"
SH
  cat >"$SHIMS/arch" <<SH
#!/bin/bash
[[ -e "$SANDBOX/rosetta" ]]
SH
  cat >"$SHIMS/softwareupdate" <<SH
#!/bin/bash
echo "\$*" >>"$SANDBOX/softwareupdate.log"
[[ \$(cat "$SANDBOX/install-result") == ok ]] && touch "$SANDBOX/rosetta"
SH
  cat >"$SHIMS/sudo" <<'SH'
#!/bin/bash
while [[ $1 == -* ]]; do shift; done
[[ $# -eq 0 ]] && exit 0
exec "$@"
SH
  chmod +x "$SHIMS"/*
  export EXTRA_ENV="PATH=$SHIMS:$PATH"
}

echo "rosetta: Intel Mac"
new_machine 0 missing
omamas $M
check "exits 0" rc_is 0
check "skips: not needed" has_output "Intel Mac: Rosetta not needed"
check "never calls softwareupdate" test ! -e "$SANDBOX/softwareupdate.log"

echo "rosetta: Apple silicon, already installed"
new_machine 1 installed
omamas $M
check "exits 0" rc_is 0
check "skips: installed" has_output "0 changed, 1 unchanged"
check "never calls softwareupdate" test ! -e "$SANDBOX/softwareupdate.log"

echo "rosetta: Apple silicon, missing"
new_machine 1 missing
omamas $M --dry-run
check "dry run reports the install" has_output "1 pending"
check "dry run installs nothing" test ! -e "$SANDBOX/softwareupdate.log"
omamas $M
check "exits 0" rc_is 0
check "installs non-interactively" grep -Fqx -- "--install-rosetta --agree-to-license" "$SANDBOX/softwareupdate.log"
check "reports success" has_output "Installed Rosetta 2"
omamas $M
check "second run changes nothing" has_output "0 changed, 1 unchanged"
check "installs only once" test "$(wc -l <"$SANDBOX/softwareupdate.log" | tr -d ' ')" = 1

echo "rosetta: install fails"
new_machine 1 missing fail
omamas $M
check "exits non-zero" rc_is 1
check "explains the consequence" has_output "Intel-only apps will not install"

finish
