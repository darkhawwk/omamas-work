#!/usr/bin/env bash
# claude-restore.sh — Restore a Claude backup made by claude-backup.sh.
#
# Opens the newest claude-*.dmg in the configured destination (or the image
# you name), checks it was made for this username and home folder (sessions
# are filed by absolute path, so they only resume when those match), then
# makes ~/.claude, ~/.claude.json and the desktop app's data match the backup.
# Whatever it replaces is copied to ~/.local/state/omamas/backups/<run-id>/
# first. Bundled Claude Code binaries and caches on this Mac are left alone.
#
# Quit the Claude app and any `claude` sessions first. Afterwards open Claude
# and sign in: credentials live in the Keychain and are never in a backup.
#
# Usage: migrate/claude-restore.sh [options] [IMAGE.dmg]
#   -n, --dry-run   Show what would change; change nothing.
#       --force     Run even if Claude is open or the user/home differ.
#   -h, --help      Show this help.

# shellcheck source=migrate/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC2034 # read by module_finish in utils.sh
MODULE_NAME=claude-restore
FORCE=0
IMAGE=""
MOUNT=""

detach_image() {
  [[ -n $MOUNT ]] || return 0
  hdiutil detach -quiet "$MOUNT" 2>/dev/null || hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true
  rmdir "$MOUNT" 2>/dev/null || true
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -n | --dry-run) export OMAMAS_DRY_RUN=1 ;;
      --force) FORCE=1 ;;
      -h | --help) __omamas_usage "$0"; exit 0 ;;
      -*) die "Unknown option: $1 (see --help)" ;;
      *) IMAGE=$1 ;;
    esac
    shift
  done
}

# Value of KEY from the backup's manifest.txt.
manifest_value() {
  sed -n "s/^$1=//p" "$MOUNT/manifest.txt" | head -n1
}

# Copy what's at ~/ITEM into this run's backup dir before it is replaced.
snapshot_existing() {
  local item=$1
  [[ -e $HOME/$item ]] || return 0
  claude_rsync "$item" "$HOME" "$OMAMAS_BACKUP_DIR/claude-restore" || return 1
  log_warn "Saved current ~/$item → $(tildify "$OMAMAS_BACKUP_DIR/claude-restore/$item")"
}

restore_item() {
  local item=$1 changes
  if [[ ! -e $MOUNT/home/$item ]]; then
    log_skip "$(tildify "$HOME/$item") not in backup"
    return 0
  fi
  if [[ ! -e $HOME/$item ]]; then
    changes=$(find "$MOUNT/home/$item" | wc -l | tr -d ' ')
  elif [[ -d $MOUNT/home/$item ]]; then
    changes=$(claude_rsync "$item" "$MOUNT/home" "$HOME" -n -i --delete | grep -c . || true)
  elif cmp -s "$MOUNT/home/$item" "$HOME/$item"; then
    changes=0
  else
    changes=1
  fi
  if ((changes == 0)); then
    log_skip "$(tildify "$HOME/$item") already matches the backup"
    return 0
  fi
  if is_dry_run; then
    log_dry "restore ~/$item ($changes changes)"
    return 0
  fi
  snapshot_existing "$item" || { log_error "Could not save current ~/$item; left it untouched"; return 0; }
  if claude_rsync "$item" "$MOUNT/home" "$HOME" --delete; then
    log_success "Restored ~/$item ($changes changes)"
  else
    log_error "Restoring ~/$item failed; previous copy is in $(tildify "$OMAMAS_BACKUP_DIR/claude-restore")"
  fi
}

main() {
  parse_args "$@"
  log_step "Claude restore"
  require_macos
  require_cmd hdiutil

  if claude_running; then
    ((FORCE)) || die "Quit the Claude app and any \`claude\` sessions first (or pass --force)."
    log_warn "Claude is running; it may overwrite restored files."
  fi

  if [[ -z $IMAGE ]]; then
    local dest
    dest=$(backup_setting destination) || die "No destination in configs/claude-backup.conf"
    IMAGE=$(ls -t "$dest"/claude-*.dmg 2>/dev/null | head -n1 || true)
    [[ -n $IMAGE ]] || die "No claude-*.dmg in $(tildify "$dest")"
  fi
  [[ -f $IMAGE ]] || die "No such image: $IMAGE"
  log_info "Image: $(tildify "$IMAGE")"

  local password
  password=$(ask_password 0)
  MOUNT=$(mktemp -d "${TMPDIR:-/tmp}/omamas-claude-restore.XXXXXX")
  add_exit_hook detach_image
  # Reading a not-yet-downloaded iCloud file downloads it first.
  printf '%s' "$password" | hdiutil attach -quiet -stdinpass -nobrowse -readonly -mountpoint "$MOUNT" "$IMAGE" ||
    die "Could not open the image (wrong password?)"
  [[ -f $MOUNT/manifest.txt ]] || die "Not an Omamas Claude backup: no manifest.txt"

  local user home me why
  user=$(manifest_value user)
  home=$(manifest_value home)
  me=$(id -un)
  log_info "Backup from $(manifest_value computer), $(manifest_value created), user $user"
  if [[ $user != "$me" || $home != "$HOME" ]]; then
    why="Backup is for $user ($home); this is $me ($HOME). Sessions are filed by path and won't resume."
    ((FORCE)) || die "$why Pass --force to restore anyway."
    log_warn "$why"
  fi

  local item
  for item in "${CLAUDE_ITEMS[@]}"; do restore_item "$item"; done

  is_dry_run || add_note "Open Claude and sign in; your sessions and settings are back."
  module_finish
}

main "$@"
