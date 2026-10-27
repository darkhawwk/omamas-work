#!/usr/bin/env bash
# 47-runtimes.sh — Install the language runtimes in ~/.config/mise/config.toml.
#
# The config is linked by the dotfiles step (configs/home/.config/mise/), so
# this runs after it. A tool counts as missing when no version of it is
# installed at all; with versions like "latest" or "lts", a Mac that already
# has one is left alone (`mise upgrade` is how you move to newer releases).
#
# "Missing" is worked out locally (tools named in the config vs `mise ls
# --installed`), never from mise's remote lookups: those silently drop tools
# whose "latest" can't be resolved, which would hide real gaps.
#
# Usage: scripts/47-runtimes.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

CONFIG="$HOME/.config/mise/config.toml"

# Tool names from the [tools] table, quotes stripped ("npm:prettier" → npm:prettier).
requested_tools() {
  awk '
    /^[[:space:]]*\[tools\][[:space:]]*$/ { on = 1; next }
    /^[[:space:]]*\[/ { on = 0 }
    on && /=/ { k = $0; sub(/[[:space:]]*=.*/, "", k); gsub(/["'\''[:space:]]/, "", k); if (k != "") print k }
  ' "$CONFIG" | sort -u
}

# "tool version" for every installed tool, from local data only. Run from
# $HOME so no project config (and its trust prompt) gets involved.
installed_tools() {
  (cd "$HOME" && MISE_OFFLINE=1 mise ls --installed 2>/dev/null) | awk '{ print $1, $2 }' | sort -u -k1,1
}

main() {
  module_start "$@"
  ensure_brew_shellenv || true
  has_cmd mise || die "mise is not installed (it's in the Brewfile); run scripts/20-packages.sh first."

  if [[ ! -f $CONFIG ]]; then
    log_skip "No $(tildify "$CONFIG")"
    module_finish
    return 0
  fi

  local installed tool version missing=""
  installed=$(installed_tools)
  while IFS= read -r tool; do
    version=$(awk -v t="$tool" '$1 == t { print $2 }' <<<"$installed")
    if [[ -n $version ]]; then
      log_skip "$tool $version"
    else
      missing+="$tool "
    fi
  done < <(requested_tools)

  if [[ -z $missing ]]; then
    module_finish
    return 0
  fi

  if is_dry_run; then
    for tool in $missing; do log_dry "install $tool with mise"; done
    module_finish
    return 0
  fi

  log_info "Installing with mise: ${missing% } (this can take a while)"
  (cd "$HOME" && MISE_YES=1 mise install) || log_warn "mise install reported errors (see output above)"

  installed=$(installed_tools)
  for tool in $missing; do
    version=$(awk -v t="$tool" '$1 == t { print $2 }' <<<"$installed")
    if [[ -n $version ]]; then
      log_success "Installed $tool $version"
    else
      log_error "$tool is still not installed"
    fi
  done

  module_finish
}

main "$@"
