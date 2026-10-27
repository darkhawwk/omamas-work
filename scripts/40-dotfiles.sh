#!/usr/bin/env bash
# 40-dotfiles.sh — Symlink every file under configs/home/ into $HOME.
#
# configs/home/ mirrors $HOME: configs/home/.config/git/config is linked to
# ~/.config/git/config. Files are linked individually (never whole directories)
# so apps can keep writing their own state next to your managed files.
# Pre-existing files are backed up; links from earlier runs whose source was
# deleted from configs/home/ are pruned.
#
# Usage: scripts/40-dotfiles.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
# shellcheck source=scripts/symlink.sh
source "$OMAMAS_SCRIPTS/symlink.sh"

SOURCE_DIR="$OMAMAS_CONFIG_DIR/home"
DESIRED=""

cleanup() { [[ -z $DESIRED ]] || rm -f "$DESIRED"; }

main() {
  module_start "$@"

  if [[ ! -d $SOURCE_DIR ]]; then
    log_skip "No $(tildify "$SOURCE_DIR") directory"
    module_finish
    return 0
  fi

  DESIRED=$(mktemp -t omamas-links)
  add_exit_hook cleanup

  local src rel
  while IFS= read -r -d '' src; do
    rel=${src#"$SOURCE_DIR"/}
    case ${rel##*/} in .DS_Store | .gitkeep) continue ;; esac
    printf '%s\t%s\n' "$HOME/$rel" "$src" >>"$DESIRED"
    link_file "$src" "$HOME/$rel" || true # failure already logged and counted
  done < <(find "$SOURCE_DIR" \( -type f -o -type l \) -print0 | sort -z)

  prune_stale_links "$DESIRED"
  # Only persist ownership when every link converged; otherwise a failed link
  # would be forgotten and never pruned later.
  ((OMAMAS_COUNT_FAILED > 0)) || save_link_state "$DESIRED"

  module_finish
}

main "$@"
