#!/usr/bin/env bash
# claude-backup.sh — Save local Claude Code and desktop-app data to an
# encrypted disk image, ready to restore on a new Mac.
#
# Writes claude-<run-id>.dmg (AES-256, password you choose) and a plain-text
# claude-<run-id>.txt summary to the destination in configs/claude-backup.conf
# (iCloud Drive by default). The image is encrypted because transcripts hold
# everything read or written in a session, and iCloud Drive is only end-to-end
# encrypted with Advanced Data Protection. Store the password in 1Password.
#
# Also lists git repos under the configured scan folder with uncommitted,
# unpushed or stashed work: commit and push those before wiping this Mac.
#
# Quit the Claude app and any `claude` sessions first, then run from Terminal.
#
# Usage: migrate/claude-backup.sh [options]
#   -n, --dry-run   Stage and size the backup and report repos; write nothing.
#       --force     Run even though Claude is open (files may be mid-write).
#   -h, --help      Show this help.

# shellcheck source=migrate/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC2034 # read by module_finish in utils.sh
MODULE_NAME=claude-backup
FORCE=0
STAGING=""

cleanup_staging() {
  # Only ever remove the mktemp directory this script created.
  [[ -n $STAGING && $STAGING == */omamas-claude-backup.* ]] && rm -rf -- "$STAGING"
  return 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -n | --dry-run) export OMAMAS_DRY_RUN=1 ;;
      --force) FORCE=1 ;;
      -h | --help) __omamas_usage "$0"; exit 0 ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
  done
}

# Print one line per repo needing attention, and a summary; never fails.
report_repos() {
  local root=$1 gitdir repo dirty unpushed stashes remote issues total=0 flagged=0
  [[ -d $root ]] || { log_info "No $(tildify "$root") to scan for repos"; return 0; }
  while IFS= read -r -d '' gitdir; do
    repo=${gitdir%/.git}
    total=$((total + 1))
    dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    remote=$(git -C "$repo" remote 2>/dev/null | head -n1)
    if [[ -n $remote ]]; then
      unpushed=$(git -C "$repo" rev-list --count --branches --not --remotes 2>/dev/null || echo 0)
    else
      unpushed=$(git -C "$repo" rev-list --count --branches 2>/dev/null || echo 0)
    fi
    stashes=$(git -C "$repo" stash list 2>/dev/null | wc -l | tr -d ' ')
    issues=""
    ((dirty == 0)) || issues+="$dirty uncommitted, "
    [[ -n $remote ]] || issues+="no remote, "
    ((unpushed == 0)) || issues+="$unpushed unpushed commits, "
    ((stashes == 0)) || issues+="$stashes stashes, "
    if [[ -n $issues ]]; then
      flagged=$((flagged + 1))
      log_warn "$(tildify "$repo"): ${issues%, }"
      printf '  %s: %s\n' "$(tildify "$repo")" "${issues%, }" >>"$STAGING/repos.txt"
    fi
  done < <(find "$root" -maxdepth 5 \( -name node_modules -o -name .Trash \) -prune -o -name .git -print0 2>/dev/null)
  if ((flagged == 0)); then
    log_info "Repos: all $total under $(tildify "$root") are committed and pushed"
  else
    log_warn "Repos: $flagged of $total under $(tildify "$root") have work that exists only on this Mac"
  fi
}

write_manifest() {
  local item size
  {
    echo "created=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "user=$(id -un)"
    echo "home=$HOME"
    echo "computer=$(scutil --get ComputerName 2>/dev/null || hostname)"
    echo "macos=$(sw_vers -productVersion)"
    echo
    echo "Contents:"
    for item in "${CLAUDE_ITEMS[@]}"; do
      if [[ -e $STAGING/home/$item ]]; then
        size=$(du -sk "$STAGING/home/$item" | cut -f1)
        printf '  ~/%s  (%s)\n' "$item" "$(awk -v k="$size" 'BEGIN { printf (k >= 1024 ? "%.1f MB" : "%d KB"), (k >= 1024 ? k / 1024 : k) }')"
      else
        printf '  ~/%s  (not present)\n' "$item"
      fi
    done
    echo
    echo "Repos with work only on this Mac:"
    if [[ -s $STAGING/repos.txt ]]; then cat "$STAGING/repos.txt"; else echo "  none"; fi
  } >"$STAGING/manifest.txt"
}

main() {
  parse_args "$@"
  log_step "Claude backup"
  require_macos
  require_cmd hdiutil

  if claude_running; then
    if is_dry_run || ((FORCE)); then
      log_warn "Claude is running; files may change while being read."
    else
      die "Quit the Claude app and any \`claude\` sessions first (or pass --force)."
    fi
  fi

  local dest scan image run=$OMAMAS_RUN_ID
  dest=$(backup_setting destination) || die "No destination in configs/claude-backup.conf"
  scan=$(backup_setting scan || true)
  image="$dest/claude-$run.dmg"
  [[ ! -e $image ]] || die "$(tildify "$image") already exists; run again in a moment."

  STAGING=$(mktemp -d "${TMPDIR:-/tmp}/omamas-claude-backup.XXXXXX")
  add_exit_hook cleanup_staging
  mkdir -p "$STAGING/payload/home"
  # The image root holds manifest.txt and home/; stage them side by side.
  local item
  for item in "${CLAUDE_ITEMS[@]}"; do
    if [[ -e $HOME/$item ]]; then
      claude_rsync "$item" "$HOME" "$STAGING/payload/home" || die "Could not copy ~/$item"
      log_info "Staged ~/$item"
    else
      log_skip "$(tildify "$HOME/$item") not present"
    fi
  done
  ln -s payload/home "$STAGING/home" # so the manifest can size items in place

  [[ -z $scan ]] || report_repos "$scan"
  write_manifest
  mv "$STAGING/manifest.txt" "$STAGING/payload/manifest.txt"
  log_info "Backup size: $(du -sh "$STAGING/payload" | cut -f1) before compression"

  if is_dry_run; then
    log_dry "write encrypted $(tildify "$image") and its summary"
    module_finish
    return 0
  fi

  local password
  password=$(ask_password 1)
  unset OMAMAS_BACKUP_PASSWORD # keep it out of every process started from here
  [[ -d $dest ]] || mkdir -p "$dest" || die "Cannot create $(tildify "$dest")"

  # Build next to the staging folder, then move: a sync client should never
  # upload a half-written image.
  printf '%s' "$password" | hdiutil create -quiet -srcfolder "$STAGING/payload" -format UDZO \
    -encryption AES-256 -stdinpass -volname OmamasClaude "$STAGING/claude.dmg" ||
    die "hdiutil could not create the image"
  mv "$STAGING/claude.dmg" "$image" || die "Could not move the image to $(tildify "$dest")"
  cp "$STAGING/payload/manifest.txt" "${image%.dmg}.txt"

  log_success "Encrypted backup: $(tildify "$image") ($(du -h "$image" | cut -f1 | tr -d ' '))"
  add_note "Keep the backup password in 1Password; without it the image can't be opened."
  log_info "Restore on the new Mac with: migrate/claude-restore.sh"
  module_finish
}

main "$@"
