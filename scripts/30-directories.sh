#!/usr/bin/env bash
# 30-directories.sh — Ensure directories from configs/directories.conf exist.
#
# Manifest format, one per line:   <path> [octal-mode]
#   ~/Work
#   ~/.ssh   700
#
# Creates missing directories and corrects modes. A non-directory occupying a
# declared path is reported as an error, never removed. Paths must stay under
# ~ (no . or .. segments), modes must be plain octal, and a symlink is never
# chmod'ed: a typo like `~/.ssh/.. 777` can't loosen your home folder.
#
# Usage: scripts/30-directories.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/directories.conf"

main() {
  module_start "$@"

  local path mode current
  while read -r path mode; do
    path=${path/#\~/$HOME}

    if [[ $path != "$HOME"/?* || /$path/ == */../* || /$path/ == */./* ]]; then
      log_error "$path: must be a path under ~ without . or .. segments"
      continue
    fi
    if [[ -n $mode && ! $mode =~ ^0?[0-7]{3}$ ]]; then
      log_error "$(tildify "$path"): mode '$mode' isn't octal like 700"
      continue
    fi
    if [[ -L $path ]]; then
      log_error "$(tildify "$path") is a symlink; not changed"
      continue
    fi
    if [[ -e $path && ! -d $path ]]; then
      log_error "$(tildify "$path") exists but is not a directory"
      continue
    fi

    if [[ ! -d $path ]]; then
      if run mkdir -p "$path" && { [[ -z $mode ]] || run chmod "$mode" "$path"; }; then
        is_dry_run || log_success "Created $(tildify "$path")${mode:+ ($mode)}"
      else
        log_error "Could not create $(tildify "$path")"
      fi
      continue
    fi

    current=$(stat -f '%Lp' "$path")
    if [[ -n $mode && $current != "${mode#0}" ]]; then
      if run chmod "$mode" "$path"; then
        is_dry_run || log_success "$(tildify "$path") mode $current → $mode"
      else
        log_error "Could not chmod $(tildify "$path")"
      fi
    else
      log_skip "$(tildify "$path")"
    fi
  done < <(read_manifest "$MANIFEST")

  module_finish
}

main "$@"
