#!/usr/bin/env bash
# 50-fonts.sh — Install font files from configs/fonts/ into ~/Library/Fonts.
#
# Fonts are copied rather than linked: macOS font services and sandboxed apps
# do not reliably follow symlinks out of ~/Library. Identical files are
# skipped; a different file with the same name is backed up, then replaced.
# Fonts published as Homebrew casks belong in the Brewfile instead.
#
# Usage: scripts/50-fonts.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

SOURCE_DIR="$OMAMAS_CONFIG_DIR/fonts"
TARGET_DIR="${OMAMAS_FONT_DIR:-$HOME/Library/Fonts}"

main() {
  module_start "$@"
  require_macos

  if [[ ! -d $SOURCE_DIR ]]; then
    log_skip "No $(tildify "$SOURCE_DIR") directory"
    module_finish
    return 0
  fi

  local src dst
  while IFS= read -r -d '' src; do
    dst="$TARGET_DIR/${src##*/}"
    if [[ -f $dst ]] && cmp -s "$src" "$dst"; then
      log_skip "${src##*/}"
      continue
    fi
    if [[ -e $dst || -L $dst ]]; then
      backup_path "$dst" || continue
    fi
    if run mkdir -p "$TARGET_DIR" && run cp -p "$src" "$dst"; then
      is_dry_run || log_success "Installed ${src##*/}"
    else
      log_error "Could not install ${src##*/}"
    fi
  done < <(find "$SOURCE_DIR" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) -print0 | sort -z)

  module_finish
}

main "$@"
