#!/usr/bin/env bash
# utils.sh — Shared runtime for every Omamas script.
#
# Sourced (never executed) by setup.sh and by each worker module. It provides:
#   * strict mode + ERR/EXIT/INT traps with readable failure reports
#   * colored, leveled telemetry ([INFO] [SKIP] [SUCCESS] [WARN] [ERROR] [DRY])
#   * dry-run aware execution (`run`)
#   * platform / privilege validation and a sudo keep-alive
#   * timestamped, path-preserving backups (`backup_path`)
#
# Compatibility contract: everything here must run on the stock macOS
# /bin/bash 3.2. That rules out associative arrays, mapfile, ${var,,},
# and bare "${arr[@]}" on possibly-empty arrays under `set -u`.

# Guard against double-sourcing (setup.sh and a worker may both pull this in).
[[ -n ${__OMAMAS_UTILS_LOADED:-} ]] && return 0
__OMAMAS_UTILS_LOADED=1

set -Eeuo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
# Canonical paths: symlinks resolved *and* the on-disk spelling. macOS disks
# are case-insensitive, so ~/work and ~/Work are one folder; without this,
# links written from one spelling look wrong from the other. realpath(1)
# returns the stored case; cd -P is the fallback.
canonical_path() { /bin/realpath "$1" 2>/dev/null || (cd -P "$1" && pwd); }
OMAMAS_SCRIPTS="$(canonical_path "$(dirname "${BASH_SOURCE[0]}")")"
OMAMAS_ROOT="$(canonical_path "$OMAMAS_SCRIPTS/..")"
OMAMAS_CONFIG_DIR="$(canonical_path "${OMAMAS_CONFIG_DIR:-$OMAMAS_ROOT/configs}")"
OMAMAS_STATE_DIR="${OMAMAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omamas}"

# One RUN_ID per orchestrated run, shared by every module so that all backups
# from a single run land in one timestamped directory.
OMAMAS_RUN_ID="${OMAMAS_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OMAMAS_BACKUP_DIR="$OMAMAS_STATE_DIR/backups/$OMAMAS_RUN_ID"
OMAMAS_DRY_RUN="${OMAMAS_DRY_RUN:-0}"
export OMAMAS_ROOT OMAMAS_SCRIPTS OMAMAS_CONFIG_DIR OMAMAS_STATE_DIR \
  OMAMAS_RUN_ID OMAMAS_BACKUP_DIR OMAMAS_DRY_RUN

# ─── Colors ───────────────────────────────────────────────────────────────────
# setup.sh decides once (before stdout becomes a tee pipe) and exports the
# answer; standalone scripts detect it themselves. NO_COLOR is honored.
if [[ -z ${OMAMAS_COLOR:-} ]]; then
  if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
    OMAMAS_COLOR=1
  else
    OMAMAS_COLOR=0
  fi
fi
export OMAMAS_COLOR

if [[ $OMAMAS_COLOR == 1 ]]; then
  C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m' C_MAGENTA=$'\033[35m' C_CYAN=$'\033[36m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
  C_BLUE='' C_MAGENTA='' C_CYAN=''
fi

# ─── Telemetry ────────────────────────────────────────────────────────────────
# Counters feed the per-module summary line printed by module_finish.
OMAMAS_COUNT_CHANGED=0
OMAMAS_COUNT_UNCHANGED=0
OMAMAS_COUNT_FAILED=0

__omamas_log() {
  local color=$1 tag=$2
  shift 2
  printf '%s%s%s %s%-9s%s %s\n' \
    "$C_DIM" "$(date +%H:%M:%S)" "$C_RESET" "$color$C_BOLD" "[$tag]" "$C_RESET" "$*"
}

log_info() { __omamas_log "$C_BLUE" INFO "$@"; }
log_warn() { __omamas_log "$C_YELLOW" WARN "$@" >&2; }

# SKIP = desired state already present. SUCCESS = state was changed.
log_skip() {
  OMAMAS_COUNT_UNCHANGED=$((OMAMAS_COUNT_UNCHANGED + 1))
  __omamas_log "$C_DIM" SKIP "$@"
}
log_success() {
  OMAMAS_COUNT_CHANGED=$((OMAMAS_COUNT_CHANGED + 1))
  __omamas_log "$C_GREEN" SUCCESS "$@"
}
log_error() {
  OMAMAS_COUNT_FAILED=$((OMAMAS_COUNT_FAILED + 1))
  __omamas_log "$C_RED" ERROR "$@" >&2
}
# A change that *would* happen; counted as a change so dry-run summaries are honest.
log_dry() {
  OMAMAS_COUNT_CHANGED=$((OMAMAS_COUNT_CHANGED + 1))
  __omamas_log "$C_MAGENTA" DRY "$@"
}

log_step() {
  printf '\n%s━━ %s ━━%s\n' "$C_CYAN$C_BOLD" "$*" "$C_RESET"
}

die() {
  log_error "$1"
  exit "${2:-1}"
}

# Pretty-print a path with $HOME collapsed to ~.
tildify() {
  case $1 in
    "$HOME" | "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Notes are deferred, human-facing follow-ups ("log out to apply X"). In an
# orchestrated run they are collected and printed once at the very end.
add_note() {
  if [[ -n ${OMAMAS_NOTES_FILE:-} ]]; then
    printf '%s\n' "$*" >>"$OMAMAS_NOTES_FILE"
  else
    log_warn "NOTE: $*"
  fi
}

# ─── Execution helpers ────────────────────────────────────────────────────────
is_dry_run() { [[ $OMAMAS_DRY_RUN == 1 ]]; }

# Print TEXT only in dry-run mode. Always succeeds, so it is safe inside
# assignments (unlike `$(is_dry_run && echo x)`, which fails under set -e).
dry_label() { if is_dry_run; then printf '%s' "$1"; fi; }

# Run a mutating command, or just describe it in dry-run mode.
#   run defaults write com.apple.dock autohide -bool true
run() {
  if is_dry_run; then
    local q
    q=$(printf '%q ' "$@")
    log_dry "${q% }"
    return 0
  fi
  "$@"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

# Run a command, killing it and everything it started after SECS seconds
# (exit 142). For anything that can block on a macOS permission prompt nobody
# is there to answer. The command gets its own process group so a child left
# holding stdout can't keep the caller waiting.
#   run_with_timeout 20 osascript -e '...'
run_with_timeout() {
  local secs=$1
  shift
  /usr/bin/perl -e '
    my $secs = shift;
    my $pid = fork // die "fork: $!";
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV or die "exec: $!" }
    $SIG{ALRM} = sub { kill "TERM", -$pid, $pid; sleep 1; kill "KILL", -$pid, $pid; exit 142 };
    alarm $secs;
    waitpid $pid, 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$secs" "$@"
}

require_cmd() {
  has_cmd "$1" || die "Required command '$1' not found.${2:+ $2}"
}

# Emit manifest lines with full-line comments and blank lines removed.
# Manifests are the State tier; this is the only way workers should read them.
read_manifest() {
  [[ -f $1 ]] || return 0
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v -e '^#' -e '^$' || true
}

# ─── Platform validation ──────────────────────────────────────────────────────
is_macos() { [[ $(uname -s) == Darwin ]]; }
require_macos() { is_macos || die "Omamas only supports macOS (found $(uname -s))."; }

require_not_root() {
  [[ $EUID -ne 0 ]] || die "Do not run as root/sudo. Omamas asks for privileges when it needs them."
}

macos_version() { sw_vers -productVersion; }

# version_ge 14.2.1 14.0  → true. Pure bash: BSD sort lacks -V on older macOS.
version_ge() {
  local IFS=.
  # shellcheck disable=SC2206
  local a=($1) b=($2) i
  for i in 0 1 2; do
    if ((${a[i]:-0} > ${b[i]:-0})); then return 0; fi
    if ((${a[i]:-0} < ${b[i]:-0})); then return 1; fi
  done
  return 0
}

# Put Homebrew on PATH for this process if it is installed but not yet in PATH
# (the norm on a fresh machine, before shell dotfiles are linked).
ensure_brew_shellenv() {
  has_cmd brew && return 0
  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x $candidate ]]; then
      eval "$("$candidate" shellenv)"
      return 0
    fi
  done
  return 1
}

# ─── Privileges ───────────────────────────────────────────────────────────────
# Ask for sudo once, then keep the ticket fresh in the background until the
# process that started the keep-alive exits. Child modules inherit
# OMAMAS_SUDO_KEEPALIVE_PID and therefore never spawn a second loop.
require_sudo() {
  if is_dry_run; then
    log_info "Dry run: skipping sudo request."
    return 0
  fi
  if ! sudo -n true 2>/dev/null; then
    log_info "Administrator privileges are required; you may be prompted for your password."
    sudo -v || die "Could not obtain sudo privileges."
  fi
  __omamas_start_sudo_keepalive
}

__omamas_start_sudo_keepalive() {
  if [[ -n ${OMAMAS_SUDO_KEEPALIVE_PID:-} ]] && kill -0 "$OMAMAS_SUDO_KEEPALIVE_PID" 2>/dev/null; then
    return 0
  fi
  local owner=$$
  (
    trap - ERR EXIT
    while kill -0 "$owner" 2>/dev/null; do
      sudo -n -v 2>/dev/null || exit 0
      sleep 45
    done
  ) >/dev/null 2>&1 &
  OMAMAS_SUDO_KEEPALIVE_PID=$!
  export OMAMAS_SUDO_KEEPALIVE_PID
  add_exit_hook __omamas_stop_sudo_keepalive
}

__omamas_stop_sudo_keepalive() {
  kill "${OMAMAS_SUDO_KEEPALIVE_PID:-}" 2>/dev/null || true
}

# ─── Backups ──────────────────────────────────────────────────────────────────
# Move an existing path into this run's backup directory, preserving its path
# relative to $HOME (or under _root/ for absolute paths elsewhere). Never
# overwrites a previous backup: collisions get a numeric suffix.
#   ~/.zshrc → ~/.local/state/omamas/backups/20261027-101500/.zshrc
# With --copy the original stays in place (for files that must never be
# absent, like PAM config, or that the user cannot move, like root-owned ones).
backup_path() {
  local verb=(mv)
  if [[ ${1:-} == --copy ]]; then
    verb=(cp -pR)
    shift
  fi
  local target=$1 rel dest n=1
  case $target in
    "$HOME"/*) rel=${target#"$HOME"/} ;;
    *) rel="_root$target" ;;
  esac
  dest="$OMAMAS_BACKUP_DIR/$rel"
  while [[ -e $dest || -L $dest ]]; do
    dest="$OMAMAS_BACKUP_DIR/$rel.$n"
    n=$((n + 1))
  done

  if is_dry_run; then
    __omamas_log "$C_MAGENTA" DRY "back up $(tildify "$target") → $(tildify "$dest")"
    return 0
  fi
  # Explicit error checks: callers often invoke this inside `if`/`||`, where
  # bash silently disables `set -e`.
  mkdir -p "$(dirname "$dest")" || { log_error "Cannot create backup dir for $target"; return 1; }
  "${verb[@]}" "$target" "$dest" || { log_error "Backup failed: $target"; return 1; }
  log_warn "Backed up $(tildify "$target") → $(tildify "$dest")"
}

# ─── Module lifecycle ─────────────────────────────────────────────────────────
# Print the leading comment block of the calling script as its --help text.
__omamas_usage() {
  sed -n '2,/^$/{s/^# \{0,1\}//p;}' "$1"
}

# Standard prologue for worker modules: parses common flags and prints a header.
#   module_start "$@"
module_start() {
  local script=${BASH_SOURCE[1]}
  MODULE_NAME=$(basename "$script" .sh)
  MODULE_NAME=${MODULE_NAME#[0-9][0-9]-}
  while [[ $# -gt 0 ]]; do
    case $1 in
      -n | --dry-run) OMAMAS_DRY_RUN=1 ;;
      -h | --help) __omamas_usage "$script"; exit 0 ;;
      *) die "Unknown option for $MODULE_NAME: $1" ;;
    esac
    shift
  done
  # Standalone runs print their own header; the orchestrator prints one for us.
  [[ -n ${OMAMAS_ORCHESTRATED:-} ]] || log_step "$MODULE_NAME"
  is_dry_run && log_info "Dry run: no changes will be made."
  return 0
}

# Standard epilogue: one summary line, non-zero exit if anything failed.
module_finish() {
  local outcome=changed
  if is_dry_run; then outcome=pending; fi
  local summary="$OMAMAS_COUNT_CHANGED $outcome, $OMAMAS_COUNT_UNCHANGED unchanged"
  if ((OMAMAS_COUNT_FAILED > 0)); then
    die "$MODULE_NAME: $summary, $OMAMAS_COUNT_FAILED failed"
  fi
  __omamas_log "$C_GREEN" SUCCESS "$MODULE_NAME: $summary"
}

# ─── Traps ────────────────────────────────────────────────────────────────────
__OMAMAS_EXIT_HOOKS=()
add_exit_hook() { __OMAMAS_EXIT_HOOKS+=("$1"); }

__omamas_on_exit() {
  local rc=$? hook
  for hook in ${__OMAMAS_EXIT_HOOKS[@]+"${__OMAMAS_EXIT_HOOKS[@]}"}; do
    "$hook" || true
  done
  exit "$rc"
}

__omamas_on_err() {
  local rc=$1 cmd=$2 line=$3 src=${4:-?}
  # Report only in the top-level shell; failures in $(...) bubble up to it.
  ((BASH_SUBSHELL == 0)) || return 0
  __omamas_log "$C_RED" ERROR "\`$cmd\` exited $rc at ${src##*/}:$line" >&2
}

trap '__omamas_on_err $? "$BASH_COMMAND" $LINENO "${BASH_SOURCE[0]}"' ERR
trap __omamas_on_exit EXIT
trap 'printf "\n"; log_error "Interrupted."; exit 130' INT TERM
