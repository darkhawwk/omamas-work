#!/usr/bin/env bash
# symlink.sh — Non-destructive symlink placement and stale-link pruning.
#
# Sourced library (not a module). Requires utils.sh.
#
#   link_file SRC DST         Ensure DST is a symlink to SRC, backing up whatever
#                             was there before. Safe to call repeatedly.
#   prune_stale_links LIST    Remove links Omamas created on a previous run whose
#                             source is no longer declared in configs/.
#   save_link_state LIST      Record LIST as the links owned by Omamas.
#
# LIST files are tab-separated "DST<TAB>SRC" lines.

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

OMAMAS_LINK_STATE="$OMAMAS_STATE_DIR/links.tsv"

# Decision table for link_file:
#   DST is a symlink → SRC              → SKIP (already converged)
#   DST resolves into the repo          → ERROR (would write into configs/)
#   DST exists (file, dir, other link)  → back up, then link
#   DST missing                         → create parents, then link
#
# Every step checks its own exit status: this function is usually called as
# `link_file a b || ...`, a context in which bash disables `set -e`.
link_file() {
  local src=$1 dst=$2 anchor anchor_real

  if [[ ! -e $src ]]; then
    log_error "Source does not exist: $src"
    return 1
  fi

  if [[ -L $dst && $(readlink "$dst") == "$src" ]]; then
    log_skip "$(tildify "$dst")"
    return 0
  fi

  # Find the nearest existing ancestor and resolve it physically. If a parent
  # directory is itself a symlink into the repo (e.g. a legacy whole-directory
  # link of ~/.config), creating DST would silently write into configs/.
  anchor=$(dirname "$dst")
  while [[ ! -d $anchor ]]; do anchor=$(dirname "$anchor"); done
  anchor_real=$(cd -P "$anchor" && pwd) || {
    log_error "Cannot resolve parent of $dst"
    return 1
  }
  case "$anchor_real/" in
    "$OMAMAS_ROOT"/* | "$OMAMAS_CONFIG_DIR"/*)
      log_error "Refusing to link $(tildify "$dst"): its parent resolves inside Omamas ($anchor_real)"
      return 1
      ;;
  esac

  # Moving or creating DST needs write access to the folder holding it. Folders
  # left owned by root (an installer run with sudo) are the usual culprit.
  if [[ -d $(dirname "$dst") && ! -w $(dirname "$dst") ]]; then
    log_error "Can't write $(tildify "$(dirname "$dst")") (owned by $(stat -f %Su "$(dirname "$dst")")). Fix: sudo chown -R $(id -un):staff $(tildify "$(dirname "$dst")")"
    return 1
  fi

  if [[ -e $dst || -L $dst ]]; then
    backup_path "$dst" || return 1
  fi

  if is_dry_run; then
    log_dry "link $(tildify "$dst") → $(tildify "$src")"
    return 0
  fi

  mkdir -p "$(dirname "$dst")" || {
    log_error "Cannot create parent directory for $dst"
    return 1
  }
  ln -s "$src" "$dst" || {
    log_error "ln failed for $dst"
    return 1
  }
  log_success "Linked $(tildify "$dst") → $(tildify "$src")"
}

# Remove links recorded in the previous run's state that are no longer
# desired. Only touches a path if it is *still* a symlink pointing at the exact
# source Omamas created it with — anything the user changed is left alone.
prune_stale_links() {
  local desired=$1 dst src
  [[ -f $OMAMAS_LINK_STATE ]] || return 0

  while IFS=$'\t' read -r dst src; do
    [[ -n $dst ]] || continue
    if cut -f1 "$desired" | grep -Fxq -- "$dst"; then
      continue
    fi
    if [[ -L $dst && $(readlink "$dst") == "$src" && ! -e $src ]]; then
      if is_dry_run; then
        log_dry "remove stale link $(tildify "$dst")"
      elif rm -- "$dst"; then
        log_success "Removed stale link $(tildify "$dst")"
      else
        log_error "Could not remove stale link $dst"
      fi
    fi
  done <"$OMAMAS_LINK_STATE"
}

save_link_state() {
  is_dry_run && return 0
  mkdir -p "$OMAMAS_STATE_DIR"
  sort -u "$1" >"$OMAMAS_LINK_STATE"
}
