#!/usr/bin/env bash
# lib.sh — Shared by migrate/claude-backup.sh and migrate/claude-restore.sh.
#
# What a Claude backup holds, relative to $HOME. Everything here is local
# Claude Code / desktop-app state; chats on claude.ai live in your account.
# Credentials stay in the Keychain and are never copied.

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/utils.sh"

# Take a password from the environment right away and remove it there, so no
# process this script starts (git, rsync, hdiutil) ever inherits it.
BACKUP_PASSWORD_ENV=${OMAMAS_BACKUP_PASSWORD:-}
unset OMAMAS_BACKUP_PASSWORD
MIN_PASSWORD=12

# shellcheck disable=SC2034 # used by claude-backup.sh and claude-restore.sh
CLAUDE_ITEMS=(
  ".claude"                              # transcripts, memory, settings, skills, plugins
  ".claude.json"                         # project trust, MCP servers, preferences
  "Library/Application Support/Claude"   # desktop app: Code-tab sessions, app state
)

# rsync excludes per item: regenerated caches, runtime state, bundled binaries,
# and Electron's Singleton* locks (restoring those stops the app launching).
# Excluded paths are also protected from --delete on restore.
claude_excludes() {
  case $1 in
    .claude)
      printf '%s\n' cache/ telemetry/ session-env/ shell-snapshots/ sessions/ ide/ statsig/ .DS_Store
      ;;
    "Library/Application Support/Claude")
      printf '%s\n' claude-code/ Cache/ "Code Cache/" GPUCache/ DawnGraphiteCache/ DawnWebGPUCache/ \
        GraphiteDawnCache/ Crashpad/ sentry/ logs/ "Singleton*" .DS_Store
      ;;
  esac
}

# rsync ITEM from SRC_ROOT to DST_ROOT (both $HOME-like). Extra rsync args first.
#   claude_rsync ITEM SRC_ROOT DST_ROOT [rsync args...]
claude_rsync() {
  local item=$1 src=$2/$1 dst=$3/$1 pattern
  shift 3
  local args=(-a "$@")
  while IFS= read -r pattern; do
    [[ -n $pattern ]] && args+=(--exclude "$pattern")
  done < <(claude_excludes "$item")
  if [[ -d $src ]]; then
    mkdir -p "$dst" && rsync "${args[@]}" "$src/" "$dst/"
  else
    mkdir -p "$(dirname "$dst")" && rsync "${args[@]}" "$src" "$dst"
  fi
}

# True if the Claude desktop app or a Claude Code CLI session is running.
claude_running() {
  ps -axo comm= | sed 's|.*/||' | grep -qxE 'Claude|claude'
}

# Read "<key> <value>" from configs/claude-backup.conf, with ~ expanded.
backup_setting() {
  local key value
  while read -r key value; do
    if [[ $key == "$1" ]]; then
      printf '%s\n' "${value/#\~/$HOME}"
      return 0
    fi
  done < <(read_manifest "$OMAMAS_CONFIG_DIR/claude-backup.conf")
  return 1
}

# Password for the encrypted image: from OMAMAS_BACKUP_PASSWORD (automation,
# tests) or typed at the terminal. CONFIRM=1 (a new backup) asks twice and
# requires MIN_PASSWORD characters either way: the image sits in iCloud, where
# a short password can be guessed offline.
ask_password() {
  local confirm=${1:-0} pw again
  if [[ -n $BACKUP_PASSWORD_ENV ]]; then
    ((!confirm || ${#BACKUP_PASSWORD_ENV} >= MIN_PASSWORD)) ||
      die "OMAMAS_BACKUP_PASSWORD is too short: use at least $MIN_PASSWORD characters."
    printf '%s' "$BACKUP_PASSWORD_ENV"
    return 0
  fi
  (: </dev/tty) 2>/dev/null || die "No terminal to ask for the backup password (or set OMAMAS_BACKUP_PASSWORD)."
  read -rsp "Backup password: " pw </dev/tty
  echo >&2
  if ((confirm)); then
    ((${#pw} >= MIN_PASSWORD)) || die "Use at least $MIN_PASSWORD characters."
    read -rsp "Repeat password: " again </dev/tty
    echo >&2
    [[ $pw == "$again" ]] || die "Passwords don't match."
  fi
  printf '%s' "$pw"
}
