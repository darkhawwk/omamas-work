#!/usr/bin/env bash
# _template.sh — Copy me to scripts/NN-<name>.sh to add a module.
#
# Reads configs/<name>.conf (one item per line) and converges each item.
#
# Usage: scripts/NN-<name>.sh [--dry-run] [--help]
#
# Module contract:
#   1. Runs standalone: sources utils.sh itself, assumes nothing about PATH or
#      about which modules ran before it (check prerequisites, don't presume).
#   2. Idempotent: every item follows check → SKIP, or act → SUCCESS.
#   3. Declarative: *what* lives in configs/, never in this file.
#   4. Mutations go through `run` (or an explicit is_dry_run branch).
#   5. Per-item failures are logged and counted, not fatal; module_finish turns
#      them into a non-zero exit after every item has had its chance.
#
# Files starting with "_" or lacking an NN- prefix are never run by setup.sh.
# Add the line `# omamas: requires-sudo` if the module may need admin rights;
# setup.sh then requests sudo up front, before any module runs.

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

MANIFEST="$OMAMAS_CONFIG_DIR/example.conf"

# Return 0 if ITEM is already in the desired state. Must have no side effects.
is_converged() {
  local item=$1
  [[ -e "$HOME/.example-$item" ]]
}

# Bring ITEM into the desired state.
converge() {
  local item=$1
  run touch "$HOME/.example-$item"
}

main() {
  module_start "$@"
  require_macos

  if [[ ! -f $MANIFEST ]]; then
    log_skip "No manifest at $(tildify "$MANIFEST")"
    module_finish
    return 0
  fi

  local item
  while IFS= read -r item; do
    if is_converged "$item"; then
      log_skip "$item"
    elif converge "$item"; then
      is_dry_run || log_success "$item"
    else
      log_error "$item"
    fi
  done < <(read_manifest "$MANIFEST")

  module_finish
}

main "$@"
