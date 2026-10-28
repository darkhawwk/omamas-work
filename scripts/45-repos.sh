#!/usr/bin/env bash
# 45-repos.sh — Clone the repos in configs/repos.conf that aren't here yet.
#
# Each <host>/<owner>/<repo> line is cloned to ~/Work/<host>/<owner>/<repo>.
# Existing checkouts are never fetched, pulled or changed. Runs after the
# dotfiles step, so ~/.ssh/config already points at 1Password's SSH agent.
#
# Access, tried in order for each repo:
#   1. SSH: works once 1Password's SSH agent is on (Settings → Developer).
#   2. HTTPS: uses your `gh auth login` if you have one; otherwise public only.
# A repo nothing can reach yet (private, no access on a fresh Mac) is reported
# with a follow-up rather than failing the run; re-run once access is set up:
#   ./setup.sh --only repos
# Every clone ends with an SSH origin, matching how you push today.
#
# Usage: scripts/45-repos.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/repos.conf"
ROOT="$HOME/Work"
PENDING=""

# Never prompt: a missing credential should fail fast, not hang the run.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"

# Exactly host/owner/repo from safe characters, with no "." or ".." parts, so
# a line can never place a clone outside ~/Work or smuggle in a URL.
REPO_PATH='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
valid_repo_path() {
  [[ $1 =~ $REPO_PATH && /$1/ != */./* && /$1/ != */../* ]]
}

ssh_url() {
  local host=${1%%/*} rest=${1#*/}
  printf 'git@%s:%s.git' "$host" "$rest"
}

# Clone PATH into DEST; prints the transport that worked.
clone() {
  local path=$1 dest=$2
  # Tests point this at local bare repos.
  local base
  base=$(test_override OMAMAS_REPOS_URL_BASE "")
  if [[ -n $base ]]; then
    git clone --quiet "$base/$path.git" "$dest" 2>/dev/null && echo local
    return
  fi
  if git clone --quiet "$(ssh_url "$path")" "$dest" 2>/dev/null; then
    echo ssh
  elif has_cmd gh && gh auth status >/dev/null 2>&1 &&
    git -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
      clone --quiet "https://$path.git" "$dest" 2>/dev/null; then
    echo "https (gh)"
  elif git clone --quiet "https://$path.git" "$dest" 2>/dev/null; then
    echo https
  else
    rm -rf -- "$dest" 2>/dev/null || true # a failed clone can leave a partial dir
    return 1
  fi
}

main() {
  module_start "$@"
  require_cmd git

  local path dest how origin
  while read -r path _; do
    valid_repo_path "$path" || { log_error "'$path' isn't <host>/<owner>/<repo>"; continue; }
    dest="$ROOT/$path"

    if [[ -e $dest/.git ]]; then
      origin=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
      case $origin in
        *"${path#*/}" | *"${path#*/}.git") log_skip "$(tildify "$dest")" ;;
        *) log_warn "$(tildify "$dest") exists with origin '${origin:-none}'; left alone" ;;
      esac
      continue
    fi
    if [[ -e $dest ]]; then
      log_error "$(tildify "$dest") exists but isn't a git checkout"
      continue
    fi
    if is_dry_run; then
      log_dry "clone $path → $(tildify "$dest")"
      continue
    fi

    mkdir -p "$(dirname "$dest")" || { log_error "Cannot create $(tildify "$(dirname "$dest")")"; continue; }
    if how=$(clone "$path" "$dest"); then
      git -C "$dest" remote set-url origin "$(ssh_url "$path")"
      log_success "Cloned $path ($how)"
    else
      log_warn "Couldn't clone $path yet: no access (private repo?)"
      PENDING+="$path "
    fi
  done < <(read_manifest "$MANIFEST")

  if [[ -n $PENDING ]]; then
    add_note "Repos not cloned yet: ${PENDING% }. Turn on 1Password's SSH agent (or run \`gh auth login\`), then: ./setup.sh --only repos"
  fi
  module_finish
}

main "$@"
