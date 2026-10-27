#!/usr/bin/env bash
# Behavior of capture.sh against a sandbox HOME and a plist-path domain.
# Brew capture is exercised only for its absence of side effects elsewhere.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

snapshot() { (cd "$FAKE_HOME" && find . -print0 | sort -z | xargs -0 stat -f '%N %z %m %p' 2>/dev/null); }

echo "capture: dotfiles"
new_sandbox
OUTDIR="$SANDBOX/out"
echo 'alias ll="ls -l"' >"$FAKE_HOME/.zshrc"
echo 'export GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz0123' >"$FAKE_HOME/.zprofile"
mkdir -p "$FAKE_HOME/.config/git" "$FAKE_HOME/.config/my app" "$FAKE_HOME/.ssh" "$FAKE_HOME/.cache"
echo '[user]' >"$FAKE_HOME/.config/git/config"
echo 'x' >"$FAKE_HOME/.config/my app/settings"
echo 'key' >"$FAKE_HOME/.ssh/id_ed25519"
echo 'history' >"$FAKE_HOME/.zsh_history"
echo 'history' >"$FAKE_HOME/.bash_history"     # last entry on a wrapped list line
echo 'old' >"$FAKE_HOME/.zshrc.bak.1789497293"
head -c 40000 /dev/zero | tr '\0' x >"$FAKE_HOME/.app-state.json"
echo 'managed' >"$CFG/home/.vimrc" && ln -s "$CFG/home/.vimrc" "$FAKE_HOME/.vimrc"
mkdir -p "$FAKE_HOME/.big" && (cd "$FAKE_HOME/.big" && for i in $(seq 1 1100); do : >"f$i"; done)
before=$(snapshot)
omamas capture.sh --only dotfiles --out "$OUTDIR"
R="$OUTDIR/dotfiles.md"
check "exits 0" rc_is 0
check "home directory is unchanged (read-only)" test "$before" = "$(snapshot)"
check "configs/ untouched" test "$(ls -A "$CFG/home")" = ".vimrc"
check "lists clean file as candidate" grep -Fq -- '- `~/.zshrc`' "$R"
check "flags file with a token" grep -Fq '`~/.zprofile` (' "$R"
check "names the secret kind" grep -Fq 'GitHub token' "$R"
check "never prints secret values" bash -c "! grep -rq ghp_ '$OUTDIR'"
check "descends into ~/.config" grep -Fq '`~/.config/git/`' "$R"
check "routes ~/.ssh to credentials" section_has "$R" "## Credentials" '~/.ssh'
check "recognizes Omamas-managed links" section_has "$R" "## Already managed" '~/.vimrc'
check "ignores history and caches" grep -Fq '.zsh_history' "$R"
check "ignores entries at list line ends" bash -c "grep '^History' '$R' | grep -q .bash_history"
check "ignores backup files" bash -c "! grep -q 'cp -p ~/.zshrc.bak' '$R' && grep '^History' '$R' | grep -q 'zshrc.bak'"
check "routes large app files to app data" section_has "$R" "## App data" '~/.app-state.json'
check "adopt command only for clean candidates" bash -c "grep -q 'cp -p ~/.zshrc configs/home/.zshrc' '$R' && ! grep -q 'cp -p ~/.zprofile' '$R'"
check "writes REVIEW.md" test -s "$OUTDIR/REVIEW.md"
check "caps file counts on huge directories" grep -Fq '`~/.big/` (1000+ files' "$R"

echo "capture: adopt commands work"
(cd "$SANDBOX" && mkdir -p configs/home && HOME="$FAKE_HOME" bash -c "$(sed -n '/^```bash$/,/^```$/p' "$R" | sed '1d;$d')")
check "copies candidate into configs/home" content_is "$CFG/home/.zshrc" 'alias ll="ls -l"'

echo "capture: macOS preferences"
new_sandbox
OUTDIR="$SANDBOX/out"
D="$SANDBOX/prefs/com.omamas.capture"
mkdir -p "$SANDBOX/prefs"
defaults write "$D" autohide -bool true
defaults write "$D" tilesize -int 48
defaults write "$D" delay -float 0.1
defaults write "$D" location -string "$FAKE_HOME/Pictures/Shots"
defaults write "$D" mod-count -int 9
defaults write "$D" KB_DoubleQuoteOption -string "“abc”"
defaults write "$D" persistent-apps -array a b
defaults write "$D" "key with space" -bool true
EXTRA_ENV="OMAMAS_CAPTURE_DOMAINS=$D" omamas capture.sh --only defaults --out "$OUTDIR"
C="$OUTDIR/macos/defaults.conf"
check "exits 0" rc_is 0
check "captures bool" grep -Eq "autohide +-bool +true$" "$C"
check "captures int" grep -Eq "tilesize +-int +48$" "$C"
check "captures float" grep -Eq "delay +-float +0.1$" "$C"
check "rewrites \$HOME as ~ for portability" grep -Eq "location +-string +~/Pictures/Shots$" "$C"
check "drops noise keys" bash -c "! grep -Eq 'mod-count|KB_DoubleQuoteOption' '$C'"
check "skips arrays and keys with spaces" bash -c "! grep -Eq 'persistent-apps|key with space' '$C'"

echo "capture: round trip through 60-macos-defaults"
mkdir -p "$CFG/macos" && cp "$C" "$CFG/macos/defaults.conf"
EXTRA_ENV="OMAMAS_NO_RESTART=1" omamas scripts/60-macos-defaults.sh
check "captured values are already converged" has_output "0 changed, 4 unchanged"

finish
