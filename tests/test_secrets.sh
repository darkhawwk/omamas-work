#!/usr/bin/env bash
# Behavior of 48-secrets.sh. `op` is a shim that resolves op://v/item/field to
# "s3cr3t-<field>"; nothing talks to 1Password.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/48-secrets.sh

# new_mac OP_STATE(ok|locked|missing)
new_mac() {
  new_sandbox
  SHIMS="$SANDBOX/shims"
  mkdir -p "$SHIMS" "$CFG/secrets/.config/tool"
  cat >"$CFG/secrets/.zshrc.local" <<'TPL'
# export UNUSED="op://Private/Commented/out"
export API_TOKEN="op://Private/Service/token"
export OTHER_KEY="op://Private/Other/credential"
TPL
  printf 'auth: op://Private/Tool/password\n' >"$CFG/secrets/.config/tool/hosts.yml"
  if [[ $1 != missing ]]; then
    cat >"$SHIMS/op" <<SH
#!/bin/bash
echo "\$*" >>"$SANDBOX/op.log"
[[ "$1" == locked ]] && { echo "[ERROR] account is not signed in" >&2; exit 1; }
[[ "$1" == waiting ]] && sleep 30 # approval prompt nobody answers
while [[ \$# -gt 0 ]]; do
  case \$1 in --in-file) in=\$2; shift ;; --out-file) out=\$2; shift ;; esac
  shift
done
sed -E 's#op://[^/]+/[^/]+/([A-Za-z]+)#s3cr3t-\1#g' "\$in" >"\$out"
SH
    chmod +x "$SHIMS/op"
  fi
  export EXTRA_ENV="PATH=$SHIMS:/usr/bin:/bin"
}

echo "secrets: render"
new_mac ok
omamas $M --dry-run
check "dry run counts references, not comments" has_output "render ~/.zshrc.local from 1Password (2 references)"
check "dry run never calls op" test ! -e "$SANDBOX/op.log"
omamas $M
check "exits 0" rc_is 0
check "fills in values" grep -qx 'export API_TOKEN="s3cr3t-token"' "$FAKE_HOME/.zshrc.local"
check "renders nested paths too" grep -qx 'auth: s3cr3t-password' "$FAKE_HOME/.config/tool/hosts.yml"
check "writes mode 600" test "$(stat -f %Lp "$FAKE_HOME/.zshrc.local")" = 600
check "never prints a secret value" lacks_output "s3cr3t"
check "leaves no rendered copies behind" bash -c "! ls -d \"\${TMPDIR:-/tmp}\"/omamas-secrets.* 2>/dev/null | grep -q ."
omamas $M
check "second run changes nothing" has_output "0 changed, 2 unchanged"

echo "secrets: template changes"
echo 'export NEW="op://Private/New/value"' >>"$CFG/secrets/.zshrc.local"
omamas $M
check "re-renders the changed file" has_output "Rendered ~/.zshrc.local (3 secrets)"
check "backs up the previous version" test -f "$(find "$(backups_dir)" -name .zshrc.local | head -n1)"
check "backup is not world-readable either" test "$(stat -f %Lp "$(find "$(backups_dir)" -name .zshrc.local | head -n1)")" = 600

echo "secrets: 1Password not ready"
new_mac locked
omamas $M
check "doesn't fail the run" rc_is 0
check "leaves a follow-up" has_output "Integrate with 1Password CLI"
check "asks 1Password only once" test "$(wc -l <"$SANDBOX/op.log" | tr -d ' ')" = 1
check "writes nothing" test ! -e "$FAKE_HOME/.zshrc.local"
new_mac missing
omamas $M
check "copes without the op CLI" has_output "1Password CLI (op) not installed"

echo "secrets: approval nobody answers"
new_mac waiting
EXTRA_ENV="$EXTRA_ENV OMAMAS_PROMPT_TIMEOUT=2"
start=$SECONDS
omamas $M
check "times out instead of waiting" test $((SECONDS - start)) -lt 10
check "says why" has_output "1Password didn't answer within 2s"
check "doesn't fail the run" rc_is 0
check "writes nothing" test ! -e "$FAKE_HOME/.zshrc.local"

echo "secrets: nothing to render"
new_mac ok
printf '# only comments\n# export X="op://Private/X/y"\n' >"$CFG/secrets/.zshrc.local"
rm -r "$CFG/secrets/.config"
omamas $M
check "skips templates without references" has_output "no secret references yet"
check "never calls op" test ! -e "$SANDBOX/op.log"

finish
