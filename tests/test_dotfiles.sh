#!/usr/bin/env bash
# Behavior of 40-dotfiles.sh + symlink.sh: linking, idempotency, backups,
# dry-run, pruning and the repo-escape guard.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/40-dotfiles.sh

echo "dotfiles: fresh link + idempotency"
new_sandbox
mkdir -p "$CFG/home/.config/git" "$CFG/home/dir with space"
echo zsh >"$CFG/home/.zshrc"
echo git >"$CFG/home/.config/git/config"
echo sp >"$CFG/home/dir with space/file name"
touch "$CFG/home/.gitkeep" "$CFG/home/.DS_Store"
omamas $M
check "exits 0" rc_is 0
check "links .zshrc" is_link_to "$FAKE_HOME/.zshrc" "$CFG/home/.zshrc"
check "links nested file, creating parents" is_link_to "$FAKE_HOME/.config/git/config" "$CFG/home/.config/git/config"
check "handles spaces in paths" is_link_to "$FAKE_HOME/dir with space/file name" "$CFG/home/dir with space/file name"
check "ignores .gitkeep/.DS_Store" test ! -e "$FAKE_HOME/.gitkeep" -a ! -e "$FAKE_HOME/.DS_Store"
check "reports 3 changed" has_output "3 changed, 0 unchanged"
omamas $M
check "second run changes nothing" has_output "0 changed, 3 unchanged"
check "second run makes no backups" test ! -d "$(backups_dir)"

echo "dotfiles: non-destructive replacement"
new_sandbox
echo new >"$CFG/home/.zshrc"
echo new >"$CFG/home/.vimrc"
echo new >"$CFG/home/.gitconfig"
mkdir -p "$CFG/home/.tool"
echo new >"$CFG/home/.tool/rc"
echo "precious" >"$FAKE_HOME/.zshrc"                    # regular file
ln -s /somewhere/else "$FAKE_HOME/.vimrc"               # foreign (broken) link
mkdir -p "$FAKE_HOME/.gitconfig" && echo x >"$FAKE_HOME/.gitconfig/inner" # dir in the way
omamas $M
B=$(ls -d "$(backups_dir)"/* 2>/dev/null | head -n1)
check "exits 0" rc_is 0
check "regular file backed up with content" content_is "$B/.zshrc" "precious"
check "foreign symlink backed up as a symlink" is_link_to "$B/.vimrc" /somewhere/else
check "directory in the way backed up whole" content_is "$B/.gitconfig/inner" x
check "all three now linked" is_link_to "$FAKE_HOME/.gitconfig" "$CFG/home/.gitconfig"
check "logs each backup" has_output "Backed up ~/.zshrc"

echo "dotfiles: dry run"
new_sandbox
echo new >"$CFG/home/.zshrc"
echo old >"$FAKE_HOME/.zshrc"
omamas $M --dry-run
check "exits 0" rc_is 0
check "prints [DRY] actions" has_output "[DRY]"
check "leaves existing file untouched" content_is "$FAKE_HOME/.zshrc" old
check "creates no backups or state" test ! -d "$FAKE_HOME/.local"

echo "dotfiles: pruning"
new_sandbox
echo a >"$CFG/home/.a"
echo b >"$CFG/home/.b"
echo c >"$CFG/home/.c"
omamas $M
rm "$CFG/home/.a" "$CFG/home/.c"
ln -sfn /user/choice "$FAKE_HOME/.c" # user re-pointed this one manually
omamas $M
check "removes link whose source was deleted" test ! -e "$FAKE_HOME/.a" -a ! -L "$FAKE_HOME/.a"
check "keeps declared link" is_link_to "$FAKE_HOME/.b" "$CFG/home/.b"
check "never touches a link the user changed" is_link_to "$FAKE_HOME/.c" /user/choice

echo "dotfiles: repo-escape guard"
new_sandbox
mkdir -p "$CFG/home/.config/app"
echo x >"$CFG/home/.config/app/conf"
ln -s "$CFG/home/.config" "$FAKE_HOME/.config" # legacy whole-dir link
omamas $M
check "exits non-zero" rc_is 1
check "explains the refusal" has_output "parent resolves inside Omamas"
check "creates no self-referencing link in configs/" test ! -L "$CFG/home/.config/app/conf"

echo "dotfiles: folder we can't write to"
new_sandbox
mkdir -p "$CFG/home/.config/tool" "$FAKE_HOME/.config/tool"
echo new >"$CFG/home/.config/tool/config"
echo old >"$FAKE_HOME/.config/tool/config"
chmod 555 "$FAKE_HOME/.config/tool"
omamas $M
chmod 755 "$FAKE_HOME/.config/tool"
check "exits non-zero" rc_is 1
check "names the folder and the fix" has_output "Can't write ~/.config/tool"
check "gives the chown command" has_output "sudo chown -R $(id -un):staff ~/.config/tool"
check "leaves the existing file in place" content_is "$FAKE_HOME/.config/tool/config" old

echo "dotfiles: backup collisions within one run id"
new_sandbox
echo new >"$CFG/home/.zshrc"
echo one >"$FAKE_HOME/.zshrc"
EXTRA_ENV="OMAMAS_RUN_ID=fixed" omamas $M
rm "$FAKE_HOME/.zshrc" && echo two >"$FAKE_HOME/.zshrc"
EXTRA_ENV="OMAMAS_RUN_ID=fixed" omamas $M
check "first backup preserved" content_is "$(backups_dir)/fixed/.zshrc" one
check "second backup gets a suffix" content_is "$(backups_dir)/fixed/.zshrc.1" two

finish
