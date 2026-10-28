#!/usr/bin/env bash
# setup.sh — Omamas local orchestrator.
#
# Validates the machine, opens a persistent log, acquires sudo once, then runs
# every scripts/NN-*.sh module in numeric order, each in its own process.
# A failing module is recorded and the run continues (unless --fail-fast);
# the exit status is non-zero if any module failed.
#
# Usage: ./setup.sh [options]
#   -n, --dry-run        Show what would change; change nothing.
#   -o, --only NAME      Run only this module (repeatable). NAME is e.g. "dotfiles".
#   -s, --skip NAME      Skip this module (repeatable).
#   -l, --list           List modules in execution order and exit.
#       --fail-fast      Stop at the first failing module.
#       --upgrade        Also upgrade outdated packages (sets OMAMAS_UPGRADE=1).
#   -h, --help           Show this help.
#
# Environment: OMAMAS_MIN_MACOS (default 14.0), OMAMAS_CONFIG_DIR, NO_COLOR.

# Decide on color while stdout is still the terminal (before tee).
if [[ -z ${OMAMAS_COLOR:-} ]]; then
  if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then OMAMAS_COLOR=1; else OMAMAS_COLOR=0; fi
  export OMAMAS_COLOR
fi

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/scripts/utils.sh"

ONLY=()
SKIP=()
LIST_ONLY=0
FAIL_FAST=0
MIN_MACOS="${OMAMAS_MIN_MACOS:-14.0}"

contains() {
  local needle=$1 item
  shift
  for item in "$@"; do [[ $item == "$needle" ]] && return 0; done
  return 1
}

module_name() {
  local n=${1##*/}
  n=${n%.sh}
  printf '%s' "${n#[0-9][0-9]-}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -n | --dry-run) OMAMAS_DRY_RUN=1 ;;
      -o | --only) ONLY+=("${2:?--only needs a module name}"); shift ;;
      -s | --skip) SKIP+=("${2:?--skip needs a module name}"); shift ;;
      -l | --list) LIST_ONLY=1 ;;
      --fail-fast) FAIL_FAST=1 ;;
      --upgrade) export OMAMAS_UPGRADE=1 ;;
      -h | --help) __omamas_usage "$0"; exit 0 ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  export OMAMAS_DRY_RUN
}

# Populate MODULES with the selected scripts, in order.
discover_modules() {
  local all=() f name
  for f in "$OMAMAS_SCRIPTS"/[0-9][0-9]-*.sh; do
    [[ -f $f ]] && all+=("$f")
  done
  ((${#all[@]} > 0)) || die "No modules found in $OMAMAS_SCRIPTS"

  # Reject typos in --only/--skip instead of silently doing nothing.
  local known=()
  for f in "${all[@]}"; do known+=("$(module_name "$f")"); done
  for name in ${ONLY[@]+"${ONLY[@]}"} ${SKIP[@]+"${SKIP[@]}"}; do
    contains "$name" "${known[@]}" || die "Unknown module '$name'. Known: ${known[*]}"
  done

  MODULES=()
  for f in "${all[@]}"; do
    name=$(module_name "$f")
    if ((${#ONLY[@]} > 0)) && ! contains "$name" "${ONLY[@]}"; then continue; fi
    if ((${#SKIP[@]} > 0)) && contains "$name" "${SKIP[@]}"; then continue; fi
    MODULES+=("$f")
  done
}

preflight() {
  log_step "Pre-flight"
  require_macos
  require_not_root

  local version
  version=$(macos_version)
  version_ge "$version" "$MIN_MACOS" || die "macOS $version is older than the supported minimum $MIN_MACOS."
  log_info "macOS $version on $(uname -m), bash $BASH_VERSION"

  [[ -d $OMAMAS_CONFIG_DIR ]] || die "Config directory missing: $OMAMAS_CONFIG_DIR"

  if [[ ${OMAMAS_SKIP_NETWORK_CHECK:-0} == 1 ]]; then
    log_info "Network check skipped"
  elif curl -fsS --max-time 5 -o /dev/null https://github.com 2>/dev/null; then
    log_info "Network reachable"
  elif is_dry_run; then
    log_warn "Network unreachable (ignored in dry run)"
  else
    die "No network connectivity (could not reach github.com)."
  fi

  local free_gb
  free_gb=$(($(df -Pk "$HOME" | awk 'NR == 2 { print $4 }') / 1024 / 1024))
  if ((free_gb < 10)); then
    log_warn "Only ${free_gb} GB free on the home volume"
  else
    log_info "${free_gb} GB free on the home volume"
  fi
}

# Prevent two runs from racing (e.g. a scheduled reconcile and a manual one).
acquire_lock() {
  LOCK_DIR="$OMAMAS_STATE_DIR/setup.lock"
  mkdir -p "$OMAMAS_STATE_DIR" && chmod 700 "$OMAMAS_STATE_DIR"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local holder
    holder=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [[ -n $holder ]] && kill -0 "$holder" 2>/dev/null; then
      die "Another Omamas run is in progress (pid $holder)."
    fi
    log_warn "Removing stale lock from pid ${holder:-unknown}"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" || die "Could not acquire lock $LOCK_DIR"
  fi
  echo $$ >"$LOCK_DIR/pid"
  add_exit_hook release_lock
}
release_lock() { rm -rf "$LOCK_DIR"; }

# Mirror all output to a timestamped log, with ANSI colors stripped.
start_logging() {
  local log_dir="$OMAMAS_STATE_DIR/logs" esc=$'\033'
  LOG_FILE="$log_dir/setup-$OMAMAS_RUN_ID$(dry_label -dry).log"
  mkdir -p "$log_dir"
  ln -sfn "$LOG_FILE" "$log_dir/latest.log"
  exec > >(tee >(sed -l "s/${esc}\[[0-9;]*m//g" >>"$LOG_FILE")) 2>&1
}

print_summary() {
  local total_seconds=$1 row name status secs color
  log_step "Summary"
  for row in ${RESULTS[@]+"${RESULTS[@]}"}; do
    IFS='|' read -r name status secs <<<"$row"
    case $status in ok) color=$C_GREEN ;; FAILED) color=$C_RED ;; *) color=$C_DIM ;; esac
    printf '  %-20s %s%-8s%s %5ss\n' "$name" "$color" "$status" "$C_RESET" "$secs"
  done
  echo
  if [[ -n ${OMAMAS_NOTES_FILE:-} && -s $OMAMAS_NOTES_FILE ]]; then
    log_info "Follow-ups:"
    sort -u "$OMAMAS_NOTES_FILE" | sed 's/^/    • /'
    echo
  fi
  log_info "Log: $(tildify "$LOG_FILE")"
  [[ ! -d $OMAMAS_BACKUP_DIR ]] || log_info "Backups: $(tildify "$OMAMAS_BACKUP_DIR")"
  if ((FAILED > 0)); then
    log_error "$FAILED module(s) failed in ${total_seconds}s. Fix and re-run; completed work will be skipped."
  else
    __omamas_log "$C_GREEN" SUCCESS "Omamas finished in ${total_seconds}s$(dry_label ' (dry run)')"
  fi
}

remove_notes_file() { rm -f "${OMAMAS_NOTES_FILE:-}"; }

main() {
  parse_args "$@"
  discover_modules

  if ((LIST_ONLY)); then
    local f
    for f in "${MODULES[@]}"; do printf '%s\t%s\n' "$(module_name "$f")" "${f#"$OMAMAS_ROOT"/}"; done
    exit 0
  fi

  acquire_lock
  start_logging
  log_info "Omamas run $OMAMAS_RUN_ID$(dry_label ' (dry run)')"
  preflight

  # Ask for privileges once, up front, so the run can proceed unattended —
  # but only if a selected module declares that it may need them, and hold
  # them only until the last such module has run. Everything after (repo
  # clones, runtime downloads, secrets) can't use them.
  local last_sudo=0 i=0 m
  for m in "${MODULES[@]}"; do
    i=$((i + 1))
    if grep -q '^# omamas: requires-sudo' "$m"; then last_sudo=$i; fi
  done
  if ((last_sudo)); then require_sudo; fi
  # Keep the machine awake for as long as this process lives.
  caffeinate -dimsu -w $$ >/dev/null 2>&1 &

  OMAMAS_NOTES_FILE=$(mktemp -t omamas-notes)
  export OMAMAS_NOTES_FILE OMAMAS_ORCHESTRATED=1
  add_exit_hook remove_notes_file

  RESULTS=()
  FAILED=0
  local start=$SECONDS name t0 status
  i=0
  for m in "${MODULES[@]}"; do
    i=$((i + 1))
    name=$(module_name "$m")
    if ((FAIL_FAST && FAILED > 0)); then
      RESULTS+=("$name|skipped|0")
      continue
    fi
    log_step "[$i/${#MODULES[@]}] $name"
    t0=$SECONDS
    # "$BASH" pins the interpreter, so a newer bash installed mid-run by
    # Homebrew can't change semantics between modules.
    if "$BASH" "$m"; then status=ok; else status=FAILED; FAILED=$((FAILED + 1)); fi
    RESULTS+=("$name|$status|$((SECONDS - t0))")
    if ((i == last_sudo)); then end_sudo; fi
  done

  print_summary $((SECONDS - start))
  exit $((FAILED > 0 ? 1 : 0))
}

main "$@"
