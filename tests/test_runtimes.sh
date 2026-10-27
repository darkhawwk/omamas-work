#!/usr/bin/env bash
# Behavior of 47-runtimes.sh. mise (and brew, so the real Homebrew mise isn't
# pulled onto PATH) are shims; nothing is downloaded.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/47-runtimes.sh

# new_mac "<installed tools>" ["<tools whose install fails>"]
new_mac() {
  new_sandbox
  SHIMS="$SANDBOX/shims"
  mkdir -p "$SHIMS" "$FAKE_HOME/.config/mise"
  cat >"$FAKE_HOME/.config/mise/config.toml" <<'TOML'
[tools]
node = "lts"
python = "latest"
"npm:prettier" = "latest"

[settings]
experimental = true
TOML
  : >"$SANDBOX/installed"
  local t
  for t in $1; do echo "$t 1.0.0" >>"$SANDBOX/installed"; done
  echo "${2:-}" >"$SANDBOX/broken"
  cat >"$SHIMS/mise" <<SH
#!/bin/bash
S="$SANDBOX"
case "\$1" in
  ls) cat "\$S/installed" ;;
  install)
    echo "cwd=\$PWD yes=\${MISE_YES:-}" >>"\$S/install.log"
    for t in node python npm:prettier; do
      grep -q "^\$t " "\$S/installed" && continue
      [[ " \$(cat "\$S/broken") " == *" \$t "* ]] && { echo "failed \$t" >&2; continue; }
      echo "\$t 2.0.0" >>"\$S/installed"
    done ;;
esac
SH
  printf '#!/bin/bash\n' >"$SHIMS/brew"
  chmod +x "$SHIMS"/*
  export EXTRA_ENV="PATH=$SHIMS:/usr/bin:/bin"
}

echo "runtimes: fresh Mac"
new_mac ""
omamas $M --dry-run
check "dry run lists 3 installs" has_output "3 pending"
check "dry run installs nothing" test ! -e "$SANDBOX/install.log"
omamas $M
check "exits 0" rc_is 0
check "runs mise install once" test "$(wc -l <"$SANDBOX/install.log" | tr -d ' ')" = 1
check "runs from \$HOME, unattended" grep -Fqx "cwd=$FAKE_HOME yes=1" "$SANDBOX/install.log"
check "reports each runtime with its version" has_output "Installed npm:prettier 2.0.0"
check "reports 3 changed" has_output "3 changed, 0 unchanged"
omamas $M
check "second run changes nothing" has_output "0 changed, 3 unchanged"
check "second run doesn't call mise install" test "$(wc -l <"$SANDBOX/install.log" | tr -d ' ')" = 1

echo "runtimes: some already installed"
new_mac "node"
omamas $M
check "keeps the installed one" has_output "node 1.0.0"
check "installs only the rest" has_output "2 changed, 1 unchanged"

echo "runtimes: an install fails"
new_mac "" "python"
omamas $M
check "exits non-zero" rc_is 1
check "names the runtime that's still missing" has_output "python is still not installed"
check "still installs the others" has_output "Installed node 2.0.0"

echo "runtimes: nothing to do"
new_mac ""
rm "$FAKE_HOME/.config/mise/config.toml"
omamas $M
check "skips without a config" has_output "No ~/.config/mise/config.toml"
rm "$SHIMS/mise"
omamas $M
check "explains when mise is missing" has_output "mise is not installed"

finish
