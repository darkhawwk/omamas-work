#!/usr/bin/env bash
# 20-packages.sh with a declared cask whose app may already be installed by
# hand. brew and sudo are shims; the "Applications" folder is in the sandbox.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/20-packages.sh

# new_mac APP_STATE(none|same|older) — cask "foo" (Foo.app, version 2.0) is declared.
new_mac() {
  new_sandbox
  SHIMS="$SANDBOX/shims" APPS="$SANDBOX/Applications"
  mkdir -p "$SHIMS" "$APPS"
  printf 'cask "foo"\n' >"$CFG/Brewfile"
  : >"$SANDBOX/installed"
  case $1 in
    same) mkdir -p "$APPS/Foo.app/Contents" && defaults write "$APPS/Foo.app/Contents/Info" CFBundleShortVersionString -string 2.0 ;;
    older) mkdir -p "$APPS/Foo.app/Contents" && defaults write "$APPS/Foo.app/Contents/Info" CFBundleShortVersionString -string 1.5 ;;
  esac
  cat >"$SHIMS/brew" <<SH
#!/bin/bash
S="$SANDBOX"
echo "\$*" >>"\$S/brew.log"
declared() { echo foo; }
missing() { for c in \$(declared); do grep -qx "\$c" "\$S/installed" || [[ " \$HOMEBREW_BUNDLE_CASK_SKIP " == *" \$c "* ]] || echo "\$c"; done; }
case "\$*" in
  "bundle list "*"--cask") declared ;;
  "bundle list "*) ;;
  "list --cask -1") cat "\$S/installed" ;;
  "info --cask foo") printf '==> foo (Foo): 2.0,abc123\nA test app\n==> Artifacts\nFoo.app (App)\n==> Analytics\n' ;;
  "install --cask --adopt foo") echo foo >>"\$S/installed" ;;
  "bundle check"*) [[ -z \$(missing) ]] ;;
  "bundle install"*) echo "skip=[\$HOMEBREW_BUNDLE_CASK_SKIP]" >>"\$S/bundle.log"; missing >>"\$S/installed" ;;
  "leaves"*) ;;
esac
SH
  cat >"$SHIMS/sudo" <<'SH'
#!/bin/bash
while [[ $1 == -* ]]; do shift; done
[[ $# -eq 0 ]] && exit 0
exec "$@"
SH
  chmod +x "$SHIMS"/*
  export EXTRA_ENV="PATH=$SHIMS:$PATH OMAMAS_APPLICATIONS_DIR=$APPS"
}
ran() { grep -Fqx -- "$1" "$SANDBOX/brew.log"; }

echo "packages: new Mac"
new_mac none
omamas $M
check "exits 0" rc_is 0
check "installs through brew bundle" grep -q '^skip=\[\]$' "$SANDBOX/bundle.log"
check "doesn't try to adopt" bash -c "! grep -q -- '--adopt' '$SANDBOX/brew.log'"
omamas $M
check "then converges" has_output "All Brewfile dependencies are installed"

echo "packages: same version installed by hand"
new_mac same
omamas $M --dry-run
check "dry run reports the adoption" has_output "adopt hand-installed Foo.app"
check "dry run adopts nothing" test ! -s "$SANDBOX/installed"
omamas $M
check "exits 0" rc_is 0
check "adopts instead of reinstalling" ran "install --cask --adopt foo"
check "never runs bundle install" test ! -e "$SANDBOX/bundle.log"
omamas $M
check "second run changes nothing" has_output "0 changed, 1 unchanged"

echo "packages: different version installed by hand"
new_mac older
omamas $M
check "exits 0" rc_is 0
check "explains it leaves the app alone" has_output "Foo.app was installed outside Homebrew (1.5 vs cask 2.0)"
check "says how to hand it to Homebrew" has_output "brew install --cask --force foo"
check "doesn't try to adopt" bash -c "! grep -q -- '--adopt' '$SANDBOX/brew.log'"
check "skips the cask instead of reinstalling" has_output "All Brewfile dependencies are installed"
check "app untouched" test "$(defaults read "$APPS/Foo.app/Contents/Info" CFBundleShortVersionString)" = 1.5

finish
