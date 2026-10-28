#!/usr/bin/env bash
# drift-check.sh — Report how this Mac differs from Omamas's configs/.
#
# Runs `setup.sh --dry-run` (changes nothing) and summarizes:
#   * modules with pending changes (a setting, app, link or Dock you changed)
#   * apps installed with Homebrew but missing from the Brewfile
#   * modules that failed
#   * uncommitted or unpushed changes in the Omamas checkout (apps writing
#     to a linked dotfile show up here)
# Writes ~/.local/state/omamas/drift/latest.txt and, when anything has
# drifted, posts a macOS notification. Run by the weekly LaunchAgent from
# 70-drift-check.sh, or by hand.
#
# Usage: scripts/drift-check.sh [--no-notify] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

NOTIFY=1
SETUP=$(test_override OMAMAS_DRIFT_SETUP "$OMAMAS_ROOT/setup.sh")
CONF="$OMAMAS_CONFIG_DIR/drift-check.conf"
REPORT_DIR="$OMAMAS_STATE_DIR/drift"
REPO="${OMAMAS_DRIFT_REPO:-$OMAMAS_ROOT}" # overridable for tests

# Title and message travel as script arguments (argv), so no text from the
# dry run can break out of the AppleScript string.
notify() {
  ((NOTIFY)) || return 0
  run_with_timeout 10 osascript \
    -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
    "$1" "$2" >/dev/null 2>&1 || true
}

main() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --no-notify) NOTIFY=0 ;;
      -h | --help) __omamas_usage "$0"; exit 0 ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
  done

  local args=(--dry-run) module output rc=0
  while read -r key module; do
    [[ $key == skip ]] && args+=(--skip "$module")
  done < <(read_manifest "$CONF")

  mkdir -p "$REPORT_DIR"
  output=$(OMAMAS_COLOR=0 HOMEBREW_NO_AUTO_UPDATE=1 "$SETUP" "${args[@]}" 2>&1) || rc=$?

  if grep -q 'Another Omamas run is in progress' <<<"$output"; then
    log_info "A setup run is in progress; skipping this check"
    return 0
  fi

  # "[SUCCESS] dock: 2 pending, 1 unchanged" → "dock (2)"
  local pending failed brew_drift repo_changes repo_ahead summary=""
  pending=$(sed -nE 's/.*\[(SUCCESS|ERROR)\] +([a-z0-9-]+): ([1-9][0-9]*) pending.*/\2 (\3)/p' <<<"$output" | paste -sd , - | sed 's/,/, /g')
  failed=$(sed -nE 's/^  ([a-z0-9-]+) +FAILED.*/\1/p' <<<"$output" | paste -sd , - | sed 's/,/, /g')
  brew_drift=$(sed -nE 's/.*Drift: installed but not in Brewfile → (.*)$/\1/p' <<<"$output" | sed 's/ *$//')
  repo_changes=$(git -C "$REPO" status --porcelain 2>/dev/null | grep -c . || true)
  repo_ahead=$(git -C "$REPO" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)

  [[ -z $pending ]] || summary+="Pending changes: $pending"$'\n'
  [[ -z $failed ]] || summary+="Failed: $failed"$'\n'
  [[ -z $brew_drift ]] || summary+="Installed but not in Brewfile: $brew_drift"$'\n'
  ((repo_changes == 0)) || summary+="Omamas repo: $repo_changes uncommitted changes"$'\n'
  ((repo_ahead == 0)) || summary+="Omamas repo: $repo_ahead unpushed commits"$'\n'
  ((rc == 0)) || [[ -n $failed ]] || summary+="setup.sh --dry-run exited $rc"$'\n'

  {
    echo "Drift check $(date '+%Y-%m-%d %H:%M') on $(scutil --get ComputerName 2>/dev/null || hostname)"
    echo
    if [[ -z $summary ]]; then echo "In sync: nothing differs from configs/."; else printf '%s' "$summary"; fi
    echo
    echo "Details: $(sed -nE 's/.*\[INFO\] +Log: (.*)$/\1/p' <<<"$output")"
    echo "Review:  cd $(tildify "$OMAMAS_ROOT") && ./setup.sh --dry-run"
  } >"$REPORT_DIR/latest.txt"

  if [[ -z $summary ]]; then
    log_success "In sync with configs/"
    return 0
  fi

  local first_line count
  count=$(grep -c . <<<"$summary")
  first_line=$(head -n1 <<<"$summary")
  while IFS= read -r line; do [[ -z $line ]] || log_warn "$line"; done <<<"$summary"
  log_info "Report: $(tildify "$REPORT_DIR/latest.txt")"
  notify "Omamas: this Mac has drifted" "$first_line$( ((count > 1)) && echo " (+$((count - 1)) more)")"
  return 0
}

main "$@"
