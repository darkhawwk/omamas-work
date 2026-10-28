#!/usr/bin/env bash
# tests/rehearse.sh against a utmctl shim: right commands, and the VM password
# never appears on a command line.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

new_sandbox
SHIM="$SANDBOX/utmctl"
cat >"$SHIM" <<SH
#!/bin/bash
echo "\$*" >>"$SANDBOX/utmctl.log"
[[ " \$* " == *" --provision-password-stdin "* ]] && cat >"$SANDBOX/stdin"
exit 0
SH
chmod +x "$SHIM"
run() { OUT=$(OMAMAS_UTMCTL="$SHIM" OMAMAS_VM_USER=el-kal OMAMAS_VM_FULL_NAME="Ben Walther" "$TEST_BASH" "$REPO/tests/rehearse.sh" "$@" 2>&1 <<<"${PW:-}"); RC=$?; }
last() { tail -n1 "$SANDBOX/utmctl.log"; }

echo "rehearse.sh"
PW=s3cret-pw run provision
check "provisions the user, auto-login and SSH" test "$(last)" = "start omamas-base --provision-username el-kal --provision-full-name Ben Walther --provision-password-stdin --provision-auto-login --provision-ssh"
check "passes the password on stdin" test "$(cat "$SANDBOX/stdin")" = s3cret-pw
check "never puts it on the command line" bash -c "! grep -q s3cret-pw '$SANDBOX/utmctl.log'"
PW="" run provision
check "refuses an empty password" rc_is 1
run start
check "starts a disposable copy" test "$(last)" = "start omamas-base --disposable"
check "prints the one-liner with the repo path" has_output "OMAMAS_DIR=~/Work/github.com/thebenwalther/omamas bash"
run stop
check "stops it" test "$(last)" = "stop omamas-base --force"
OMAMAS_VM=other run start
check "honors OMAMAS_VM" bash -c "OMAMAS_UTMCTL='$SHIM' OMAMAS_VM=other '$TEST_BASH' '$REPO/tests/rehearse.sh' start >/dev/null; tail -n1 '$SANDBOX/utmctl.log' | grep -q '^start other --disposable$'"
run bogus
check "rejects unknown commands" rc_is 1

finish
