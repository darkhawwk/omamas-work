#!/usr/bin/env bash
# migrate/claude-backup.sh and claude-restore.sh, end to end: a real encrypted
# image made from a fake home, restored onto a simulated new Mac. `ps` is a
# shim so "is Claude running" is deterministic.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
B=migrate/claude-backup.sh
R=migrate/claude-restore.sh
PW=correct-horse-9

setup_home() {
  new_sandbox
  SHIMS="$SANDBOX/shims"
  DEST="$SANDBOX/icloud/OmamasClaude"
  APPDATA="$FAKE_HOME/Library/Application Support/Claude"
  mkdir -p "$SHIMS" "$FAKE_HOME/.claude/projects/-Users-x-Work" "$FAKE_HOME/.claude/cache" \
    "$APPDATA/claude-code-sessions" "$APPDATA/Cache" "$APPDATA/claude-code/1.0" "$FAKE_HOME/Work"
  echo '{"msg":"hello"}' >"$FAKE_HOME/.claude/projects/-Users-x-Work/s1.jsonl"
  echo junk >"$FAKE_HOME/.claude/cache/c"
  echo '{"trust":true}' >"$FAKE_HOME/.claude.json"
  echo '{"session":1}' >"$APPDATA/claude-code-sessions/a.json"
  echo cache >"$APPDATA/Cache/x"
  echo binary >"$APPDATA/claude-code/1.0/claude"
  ln -s /nonexistent "$APPDATA/SingletonLock"
  printf 'destination  %s\nscan         ~/Work\n' "$DEST" >"$CFG/claude-backup.conf"
  running none
}

# running none|app → what the ps shim reports
running() {
  if [[ $1 == app ]]; then
    printf '#!/bin/bash\necho /Applications/Claude.app/Contents/MacOS/Claude\n' >"$SHIMS/ps"
  else
    printf '#!/bin/bash\necho /usr/bin/login\n' >"$SHIMS/ps"
  fi
  chmod +x "$SHIMS/ps"
  export EXTRA_ENV="PATH=$SHIMS:$PATH OMAMAS_BACKUP_PASSWORD=$PW"
}

git_q() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@" -q; }

echo "claude-backup"
setup_home
git_q init --bare "$SANDBOX/remote.git"
git_q clone "$SANDBOX/remote.git" "$FAKE_HOME/Work/clean" 2>/dev/null
(cd "$FAKE_HOME/Work/clean" && echo a >a && git add a && git_q commit -m a && git_q push origin main)
git_q init "$FAKE_HOME/Work/local-only"
echo wip >"$FAKE_HOME/Work/local-only/wip.txt"

running app
omamas $B
check "refuses while Claude is running" rc_is 1
check "says to quit Claude" has_output "Quit the Claude app"

omamas $B --dry-run
check "dry run works while Claude runs" rc_is 0
check "dry run writes nothing" test ! -e "$DEST"
check "flags the repo with local-only work" has_output "~/Work/local-only: 1 uncommitted, no remote"
check "doesn't flag the pushed repo" lacks_output "~/Work/clean:"

running none
omamas $B
IMG=$(ls "$DEST"/claude-*.dmg 2>/dev/null | head -n1)
check "exits 0" rc_is 0
check "writes an encrypted image" test -f "$IMG"
check "writes a plain summary next to it" test -f "${IMG%.dmg}.txt"
check "summary lists repos at risk" grep -q 'local-only: 1 uncommitted' "${IMG%.dmg}.txt"
check "summary never contains the password" bash -c "! grep -q '$PW' '${IMG%.dmg}.txt'"
check "image needs the password" bash -c "printf wrong | hdiutil attach -quiet -stdinpass -nobrowse -readonly -mountpoint '$SANDBOX/m' '$IMG' 2>/dev/null; test \$? -ne 0"
check "leaves no staging behind" bash -c "! ls -d \"\${TMPDIR:-/tmp}\"/omamas-claude-backup.* 2>/dev/null | grep -q ."

echo "claude-restore onto a new Mac"
# New Mac: no Claude data, except what a fresh app creates on first launch.
rm -rf "$FAKE_HOME/.claude" "$FAKE_HOME/.claude.json" "$APPDATA"
mkdir -p "$APPDATA/claude-code/2.0" "$APPDATA/Cache" "$APPDATA/claude-code-sessions"
echo new-binary >"$APPDATA/claude-code/2.0/claude"
echo fresh >"$APPDATA/Cache/y"
echo stale >"$APPDATA/claude-code-sessions/fresh-install.json"

omamas $R --dry-run
check "dry run reports pending restores" has_output "3 pending"
check "dry run restores nothing" test ! -e "$FAKE_HOME/.claude"

running app
omamas $R
check "refuses while Claude is running" rc_is 1
running none

EXTRA_ENV="PATH=$SHIMS:$PATH OMAMAS_BACKUP_PASSWORD=wrong-password" omamas $R
check "wrong password is refused" has_output "wrong password?"

omamas $R
check "exits 0" rc_is 0
check "restores transcripts" content_is "$FAKE_HOME/.claude/projects/-Users-x-Work/s1.jsonl" '{"msg":"hello"}'
check "restores ~/.claude.json" content_is "$FAKE_HOME/.claude.json" '{"trust":true}'
check "restores desktop sessions" content_is "$APPDATA/claude-code-sessions/a.json" '{"session":1}'
check "drops state the backup didn't have" test ! -e "$APPDATA/claude-code-sessions/fresh-install.json"
check "keeps this Mac's bundled Claude Code" content_is "$APPDATA/claude-code/2.0/claude" new-binary
check "keeps this Mac's caches" content_is "$APPDATA/Cache/y" fresh
check "never restores caches" test ! -e "$FAKE_HOME/.claude/cache/c" -a ! -e "$APPDATA/Cache/x"
check "never restores Electron locks" test ! -L "$APPDATA/SingletonLock"
check "snapshots what it replaced" test -f "$(find "$(backups_dir)" -name fresh-install.json | head -n1)"
check "unmounts the image" bash -c "! mount | grep -q omamas-claude-restore"
omamas $R
check "second restore changes nothing" has_output "0 changed, 3 unchanged"

echo "claude-restore: different home folder"
KEEP=$(mktemp "${TMPDIR:-/tmp}/omamas-test-image.XXXXXX")
cp "$IMG" "$KEEP"
setup_home # a fresh sandbox: different $HOME, same user
OLD_IMG="$SANDBOX/from-old-mac.dmg"
mv "$KEEP" "$OLD_IMG"
omamas $R "$OLD_IMG"
check "refuses a backup made for another home" has_output "Sessions are filed by path"
omamas $R --force "$OLD_IMG"
check "--force restores anyway" rc_is 0

finish
