#!/usr/bin/env bash
# Behavior of 45-repos.sh against local bare repos standing in for GitHub.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
M=scripts/45-repos.sh

git_q() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false -c tag.gpgsign=false "$@" -q; }

# Remotes: me/a and me/b exist; me/private does not (stands in for no access).
new_remotes() {
  new_sandbox
  local r
  for r in a b; do
    git_q init --bare "$SANDBOX/remotes/github.com/me/$r.git"
    git_q clone "$SANDBOX/remotes/github.com/me/$r.git" "$SANDBOX/seed-$r" 2>/dev/null
    (cd "$SANDBOX/seed-$r" && echo "$r" >README && git add README && git_q commit -m init && git_q push origin main)
  done
  printf '# comment\n\ngithub.com/me/a\ngithub.com/me/b\ngithub.com/me/private\n' >"$CFG/repos.conf"
  export EXTRA_ENV="OMAMAS_REPOS_URL_BASE=file://$SANDBOX/remotes"
}
W() { echo "$FAKE_HOME/Work/github.com/me/$1"; }

echo "repos: fresh Mac"
new_remotes
omamas $M --dry-run
check "dry run reports 3 clones" has_output "3 pending"
check "dry run clones nothing" test ! -e "$FAKE_HOME/Work"
omamas $M
check "exits 0 even with an unreachable repo" rc_is 0
check "clones to ~/Work/<host>/<owner>/<repo>" content_is "$(W a)/README" a
check "clones every reachable repo" content_is "$(W b)/README" b
check "sets an SSH origin" test "$(git -C "$(W a)" remote get-url origin)" = "git@github.com:me/a.git"
check "leaves no partial dir for the unreachable one" test ! -e "$(W private)"
check "warns about it" has_output "Couldn't clone github.com/me/private yet"
check "leaves a follow-up with the re-run command" has_output "./setup.sh --only repos"
omamas $M
check "second run skips existing checkouts" has_output "0 changed, 2 unchanged"

echo "repos: existing work is never touched"
new_remotes
mkdir -p "$(W a)"
git_q init "$(W a)"
git -C "$(W a)" remote add origin git@github.com:someone-else/a.git
echo local >"$(W a)/wip.txt"
mkdir -p "$(W b)" && echo x >"$(W b)/notes.txt"
printf 'github.com/me/a\ngithub.com/me/b\nnot-a-path\ngithub.com/../escape\n/etc/x/y\ngithub.com/me/a;rm\n' >"$CFG/repos.conf"
omamas $M
check "warns about a checkout with another origin" has_output "exists with origin 'git@github.com:someone-else/a.git'; left alone"
check "keeps uncommitted work there" content_is "$(W a)/wip.txt" local
check "refuses a non-git folder in the way" has_output "exists but isn't a git checkout"
check "keeps that folder's files" content_is "$(W b)/notes.txt" x
check "rejects a malformed line" has_output "'not-a-path' isn't <host>/<owner>/<repo>"
check "rejects .. (can't escape ~/Work)" has_output "'github.com/../escape' isn't <host>/<owner>/<repo>"
check "rejects absolute paths" has_output "'/etc/x/y' isn't <host>/<owner>/<repo>"
check "rejects shell characters" has_output "'github.com/me/a;rm' isn't <host>/<owner>/<repo>"
check "creates nothing outside ~/Work" test ! -e "$FAKE_HOME/escape" -a ! -e "$FAKE_HOME/Work/escape"
check "exits non-zero for those errors" rc_is 1

finish
