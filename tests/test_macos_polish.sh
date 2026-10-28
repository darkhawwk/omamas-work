#!/usr/bin/env bash
# 62-dock, 64-default-apps, 66-login-items and 17-security. dockutil, duti,
# osascript, socketfilterfw, fdesetup, sudo and killall are all shims, so the
# real Dock, defaults, login items and firewall are never touched.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

new_mac() {
  new_sandbox
  SHIMS="$SANDBOX/shims" APPS="$SANDBOX/Applications" ST="$SANDBOX/state"
  mkdir -p "$SHIMS" "$CFG/macos" "$ST" "$APPS/Zed.app" "$APPS/Brave Browser.app/Contents" "$APPS/Rectangle.app" "$APPS/Obsidian.app/Contents"
  defaults write "$APPS/Brave Browser.app/Contents/Info" CFBundleIdentifier -string com.brave.Browser
  defaults write "$APPS/Obsidian.app/Contents/Info" CFBundleIdentifier -string md.obsidian
  cat >"$SHIMS/lsregister" <<SH
#!/bin/bash
echo "\$2" >>"$ST/lsregister.log"
id=\$(defaults read "\$2/Contents/Info" CFBundleIdentifier | tr '[:upper:]' '[:lower:]')
touch "$ST/registered-\$id"
SH
  : >"$ST/dock" && : >"$ST/login" && : >"$ST/handlers"
  printf '#!/bin/bash\necho "killall $*" >>"%s/killed"\n' "$SANDBOX" >"$SHIMS/killall"
  printf '#!/bin/bash\nwhile [[ $1 == -* ]]; do shift; done\n[[ $# -eq 0 ]] && exit 0\nexec "$@"\n' >"$SHIMS/sudo"
  printf '#!/bin/bash\nexit 0\n' >"$SHIMS/brew"
  cat >"$SHIMS/dockutil" <<SH
#!/bin/bash
case "\$1" in
  --list) while IFS=\$'\t' read -r sec path; do printf 'x\tfile://%s/\t%s\tplist\n' "\${path// /%20}" "\$sec"; done <"$ST/dock" ;;
  --remove) : >"$ST/dock" ;;
  --add) printf 'persistentApps\t%s\n' "\$2" >>"$ST/dock" ;;
esac
SH
  cat >"$SHIMS/duti" <<SH
#!/bin/bash
if [[ \$1 == -d ]]; then awk -v t="\$2" '\$1 == t { print \$2 }' "$ST/handlers"; exit; fi
# -s ID TARGET [ROLE]; browser changes stay pending until "confirmed".
id=\$(tr '[:upper:]' '[:lower:]' <<<"\$2")
# Like macOS: an app Launch Services hasn't registered yet can't become a
# default (silently for document types, an error for link types).
if [[ \$id != com.apple.safari && ! -e "$ST/registered-\$id" ]]; then [[ -n \$4 ]] && exit 0 || exit 1; fi
[[ -e "$ST/duti-hangs" && (\$3 == http || \$3 == https) ]] && sleep 30
[[ -e "$ST/no-confirm" && \$3 == https ]] && exit 1
[[ -e "$ST/no-confirm" && \$3 == http ]] && exit 0
grep -v "^\$3 " "$ST/handlers" >"$ST/h.tmp"; echo "\$3 \$2" >>"$ST/h.tmp"; mv "$ST/h.tmp" "$ST/handlers"
SH
  cat >"$SHIMS/osascript" <<SH
#!/bin/bash
[[ -e "$ST/se-denied" ]] && { echo "Not authorized to send Apple events (-1743)" >&2; exit 1; }
[[ -e "$ST/se-hangs" ]] && sleep 30
case "\$*" in
  *"get the path of every login item"*) paste -sd , "$ST/login" | sed 's/,/, /g' ;;
  # Real osascript passes trailing arguments to "on run argv": path, hidden.
  *"make login item"*) args=("\$@"); echo "\${args[\$#-2]}" >>"$ST/login"; echo "\${args[\$#-1]}" >>"$ST/login-hidden"
     echo "\$*" >>"$ST/osascript.log" ;;
esac
SH
  cat >"$SHIMS/socketfilterfw" <<SH
#!/bin/bash
case "\$1" in
  --getglobalstate) if [[ \$(cat "$ST/fw" 2>/dev/null) == on ]]; then echo "Firewall is enabled. (State = 1)"; else echo "Firewall is disabled. (State = 0)"; fi ;;
  --getstealthmode) echo "Firewall stealth mode is \$(cat "$ST/stealth" 2>/dev/null || echo off)" ;;
  --setglobalstate) echo "\$2" >"$ST/fw" ;;
  --setstealthmode) echo "\$2" >"$ST/stealth" ;;
esac
SH
  printf '#!/bin/bash\necho "FileVault is $(cat %s/fv 2>/dev/null || echo On)."\n' "$ST" >"$SHIMS/fdesetup"
  chmod +x "$SHIMS"/*
  export EXTRA_ENV="PATH=$SHIMS:/usr/bin:/bin:/usr/sbin OMAMAS_SOCKETFILTERFW=$SHIMS/socketfilterfw OMAMAS_PROMPT_TIMEOUT=2 OMAMAS_LSREGISTER=$SHIMS/lsregister OMAMAS_APPLICATIONS_DIR=$APPS"
}
dock_apps() { awk -F'\t' '$1 == "persistentApps" { print $2 }' "$ST/dock" | paste -sd '|' -; }

echo "dock"
new_mac
printf 'persistentApps\t/System/Applications/Mail.app\npersistentOthers\t%s/Downloads\n' "$FAKE_HOME" >"$ST/dock"
printf '%s\n%s\n%s\n' "$APPS/Brave Browser.app" "$APPS/Missing.app" "$APPS/Zed.app" >"$CFG/macos/dock.conf"
omamas scripts/62-dock.sh --dry-run
check "dry run reports the rebuild" has_output "set the Dock to 2 apps and no folders (now 1 apps, 1 folders)"
check "dry run changes nothing" test "$(dock_apps)" = /System/Applications/Mail.app
omamas scripts/62-dock.sh
check "exits 0" rc_is 0
check "exactly the declared apps, in order" test "$(dock_apps)" = "$APPS/Brave Browser.app|$APPS/Zed.app"
check "removes folders and stacks" bash -c "! grep -q persistentOthers '$ST/dock'"
check "skips apps that aren't installed" has_output "Not installed, left out of the Dock: $APPS/Missing.app"
check "restarts the Dock once" grep -qx "killall Dock" "$SANDBOX/killed"
omamas scripts/62-dock.sh
check "second run changes nothing" has_output "0 changed, 1 unchanged"
: >"$CFG/macos/dock.conf"
omamas scripts/62-dock.sh
check "an empty list empties the Dock" test -z "$(dock_apps)"
rm "$CFG/macos/dock.conf"
printf 'persistentApps\t/System/Applications/Mail.app\n' >"$ST/dock"
omamas scripts/62-dock.sh
check "no dock.conf leaves the Dock alone" test "$(dock_apps)" = /System/Applications/Mail.app

echo "default apps"
new_mac
printf 'http com.apple.Safari\npublic.html com.apple.Safari\n' >"$ST/handlers"
printf 'com.brave.Browser http\nmd.obsidian net.daringfireball.markdown all\nCOM.APPLE.SAFARI public.html all\n' >"$CFG/macos/default-apps.conf"
omamas scripts/64-default-apps.sh
check "exits 0" rc_is 0
check "sets a URL scheme" grep -qx "http com.brave.Browser" "$ST/handlers"
check "sets a document type" grep -qx "net.daringfireball.markdown md.obsidian" "$ST/handlers"
check "logs the previous handler" has_output "http → com.brave.Browser (was: com.apple.Safari)"
check "compares bundle ids case-insensitively" has_output "public.html → COM.APPLE.SAFARI"
check "registers freshly installed apps first" grep -Fqx "$APPS/Obsidian.app" "$ST/lsregister.log"
check "registers each app once" test "$(grep -c . "$ST/lsregister.log")" = 2
omamas scripts/64-default-apps.sh
check "second run changes nothing" has_output "0 changed, 3 unchanged"
new_mac
printf 'http com.apple.Safari\nhttps com.apple.Safari\n' >"$ST/handlers"
printf 'com.brave.Browser http\ncom.brave.Browser https\n' >"$CFG/macos/default-apps.conf"
touch "$ST/no-confirm"
omamas scripts/64-default-apps.sh
check "unconfirmed browser change isn't reported as done" lacks_output "http → com.brave.Browser (was"
check "https erroring while the dialog is open is pending, not a failure" rc_is 0
check "asks you to confirm macOS's dialog" has_output "Default apps not applied yet: http https"

new_mac
printf 'com.example.Missing public.html all\n' >"$CFG/macos/default-apps.conf"
omamas scripts/64-default-apps.sh
check "an app that isn't installed is an error" has_output "no app with bundle id com.example.Missing is installed"
check "and fails the module" rc_is 1

new_mac
printf 'http com.apple.Safari\n' >"$ST/handlers"
printf 'com.brave.Browser http\n' >"$CFG/macos/default-apps.conf"
touch "$ST/duti-hangs"
start=$SECONDS
omamas scripts/64-default-apps.sh
check "a dialog nobody answers times out" test $((SECONDS - start)) -lt 10
check "and becomes a follow-up, not a failure" has_output "waiting for you to confirm com.brave.Browser in macOS's dialog"
check "exits 0" rc_is 0

echo "login items"
new_mac
echo "$APPS/Rectangle.app" >"$ST/login"
printf '%s\n%s hidden\n%s\n' "$APPS/Rectangle.app" "$APPS/Brave Browser.app" "$APPS/Missing.app" >"$CFG/macos/login-items.conf"
omamas scripts/66-login-items.sh --dry-run
check "dry run lists the addition" has_output "open Brave Browser at login (hidden)"
check "dry run adds nothing" test "$(wc -l <"$ST/login" | tr -d ' ')" = 1
omamas scripts/66-login-items.sh
check "exits 0" rc_is 0
check "adds a path with spaces" grep -Fqx "$APPS/Brave Browser.app" "$ST/login"
check "passes the hidden flag" grep -qx true "$ST/login-hidden"
check "passes values as arguments, not script text" bash -c "! grep -q 'path:\"' '$ST/osascript.log'"
check "keeps existing items" has_output "Rectangle"
check "skips apps that aren't installed" has_output "Not installed, not added: $APPS/Missing.app"
omamas scripts/66-login-items.sh
check "second run changes nothing" has_output "0 changed, 2 unchanged"
touch "$ST/se-denied"
omamas scripts/66-login-items.sh
check "permission denied doesn't fail the run" rc_is 0
check "explains where to allow it" has_output "Privacy & Security → Automation"
rm "$ST/se-denied" && touch "$ST/se-hangs"
start=$SECONDS
omamas scripts/66-login-items.sh
check "an unanswered prompt times out" test $((SECONDS - start)) -lt 10
check "and leaves a follow-up" has_output "./setup.sh --only login-items"

echo "security"
new_mac
printf 'firewall on\nstealth on\nfilevault check\n' >"$CFG/macos/security.conf"
omamas scripts/17-security.sh --dry-run
check "reads a disabled firewall as off" has_output "firewall: off → on"
omamas scripts/17-security.sh
check "exits 0" rc_is 0
check "turns the firewall on" test "$(cat "$ST/fw")" = on
check "turns stealth mode on" test "$(cat "$ST/stealth")" = on
check "reports FileVault" has_output "FileVault on"
omamas scripts/17-security.sh
check "second run changes nothing" has_output "0 changed, 3 unchanged"
echo Off >"$ST/fv"
omamas scripts/17-security.sh
check "FileVault off is a warning with a follow-up" has_output "Turn on FileVault"
echo "security: overrides only in test mode"
new_mac
printf 'firewall on\n' >"$CFG/macos/security.conf"
printf '#!/bin/bash\ntouch %s/planted-ran\necho "Firewall is enabled. (State = 1)"\n' "$SANDBOX" >"$SANDBOX/planted"
chmod +x "$SANDBOX/planted"
EXTRA_ENV="$EXTRA_ENV OMAMAS_SOCKETFILTERFW=$SANDBOX/planted OMAMAS_TEST_MODE=0" omamas scripts/17-security.sh --dry-run
check "a planted override is ignored outside test mode" test ! -e "$SANDBOX/planted-ran"
EXTRA_ENV="$EXTRA_ENV OMAMAS_SOCKETFILTERFW=$SANDBOX/planted" omamas scripts/17-security.sh --dry-run
check "and honored in test mode" test -e "$SANDBOX/planted-ran"

printf 'firewall maybe\n' >"$CFG/macos/security.conf"
omamas scripts/17-security.sh
check "rejects values other than on/off" has_output "firewall must be on or off"

finish
