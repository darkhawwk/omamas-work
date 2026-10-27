#!/usr/bin/env bash
# Behavior of 02-computer-name.sh. scutil and sudo are shims; nothing is renamed.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/02-computer-name.sh

# new_mac NAME → a Mac whose three names are all NAME (or unset if empty).
new_mac() {
  new_sandbox
  SHIMS="$SANDBOX/shims"
  mkdir -p "$SHIMS" "$SANDBOX/scutil" "$CFG/macos"
  local key
  if [[ -n $1 ]]; then
    for key in ComputerName LocalHostName HostName; do printf '%s' "$1" >"$SANDBOX/scutil/$key"; done
  fi
  cat >"$SHIMS/scutil" <<SH
#!/bin/bash
case "\$1" in
  --get) cat "$SANDBOX/scutil/\$2" 2>/dev/null || { echo "\$2: not set" >&2; exit 1; } ;;
  --set) printf '%s' "\$3" >"$SANDBOX/scutil/\$2"; echo "\$2" >>"$SANDBOX/set.log" ;;
esac
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
name() { cat "$SANDBOX/scutil/$1"; }

echo "computer-name: new Mac"
new_mac "Ben's MacBook Pro"
echo "Bizarro" >"$CFG/macos/computer-name.conf"
omamas $M --dry-run
check "dry run reports 3 changes" has_output "3 pending"
check "dry run renames nothing" test "$(name ComputerName)" = "Ben's MacBook Pro"
omamas $M
check "exits 0" rc_is 0
check "sets ComputerName" test "$(name ComputerName)" = Bizarro
check "sets LocalHostName" test "$(name LocalHostName)" = Bizarro
check "sets HostName" test "$(name HostName)" = Bizarro
check "logs the old name" has_output "(was: Ben's MacBook Pro)"
omamas $M
check "second run changes nothing" has_output "0 changed, 3 unchanged"

echo "computer-name: unset names and a name with spaces"
new_mac ""
printf '# comment\n\nBizarro Studio 2\n' >"$CFG/macos/computer-name.conf"
omamas $M
check "keeps the friendly name as written" test "$(name ComputerName)" = "Bizarro Studio 2"
check "derives a valid network name" test "$(name LocalHostName)" = "Bizarro-Studio-2"
check "HostName matches LocalHostName" test "$(name HostName)" = "Bizarro-Studio-2"

echo "computer-name: already named"
new_mac Bizarro
echo Bizarro >"$CFG/macos/computer-name.conf"
omamas $M
check "changes nothing" has_output "0 changed, 3 unchanged"
check "never calls scutil --set" test ! -e "$SANDBOX/set.log"

echo "computer-name: no name configured"
new_mac Bizarro
omamas $M
check "skips without a config" has_output "No name in"

finish
