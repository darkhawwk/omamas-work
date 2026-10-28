#!/usr/bin/env bash
# 48-secrets.sh — Render secret files from 1Password references.
#
# Every file under configs/secrets/ is a template for the same path under
# $HOME (configs/secrets/.zshrc.local → ~/.zshrc.local). Templates contain
# op://<vault>/<item>/<field> references, never values; `op inject` fills them
# in and the result is written with mode 600. Values never enter git, logs or
# backups' names; only "changed" or "unchanged" is reported.
#
# Shell files (.zshrc*, .zshenv*, .zprofile*, .bashrc*, .profile*, *.sh,
# *.zsh) skip `op inject`: it pastes values unescaped, so a value holding a
# quote, $ or backtick would run as code every time the shell sources the
# file. They may contain only comments, blank lines and
#   export NAME="op://<vault>/<item>/<field>"
# Each value is fetched with `op read` and written single-quoted.
#
#   No references in a template   → SKIP (nothing to render yet)
#   Rendered output already there  → SKIP
#   Differs or missing             → back up the old file, write the new one
#   1Password CLI unavailable      → follow-up note, not a failure: turn on
#                                    1Password → Settings → Developer →
#                                    "Integrate with 1Password CLI", then
#                                    ./setup.sh --only secrets
#
# Usage: scripts/48-secrets.sh [--dry-run] [--help]

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

SOURCE_DIR="$OMAMAS_CONFIG_DIR/secrets"
# op waits while 1Password asks you to approve (Touch ID); don't wait forever.
TIMEOUT="${OMAMAS_PROMPT_TIMEOUT:-120}"
RENDER_DIR=""

cleanup_render() {
  # Rendered secrets live here briefly; never leave them behind.
  [[ -n $RENDER_DIR && $RENDER_DIR == */omamas-secrets.* ]] && rm -rf -- "$RENDER_DIR"
  return 0
}

SHELL_EXPORT='^export ([A-Za-z_][A-Za-z0-9_]*)="(op://[^"]+)"$'
BAD_LINE=""

is_shell_file() {
  case ${1##*/} in
    .zshrc* | .zshenv* | .zprofile* | .bashrc* | .bash_profile* | .profile* | *.sh | *.zsh) return 0 ;;
  esac
  return 1
}

# shell_quote VALUE: VALUE in single quotes, safe for any shell to source.
shell_quote() {
  local sq="'\\''"
  printf "'%s'" "${1//\'/$sq}"
}

# render_shell TEMPLATE OUT. Returns 3 (line number in BAD_LINE) on a line
# that isn't allowed, or op's exit code. The value stays in a variable:
# never on a command line, never in a log.
render_shell() {
  local line name value n=0 rc
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    if [[ -z ${line//[[:space:]]/} || $line =~ ^[[:space:]]*# ]]; then
      printf '%s\n' "$line"
    elif [[ $line =~ $SHELL_EXPORT ]]; then
      name=${BASH_REMATCH[1]}
      rc=0
      value=$(run_with_timeout "$TIMEOUT" op read --no-newline "${BASH_REMATCH[2]}") || rc=$?
      ((rc == 0)) || return "$rc"
      printf 'export %s=%s\n' "$name" "$(shell_quote "$value")"
    else
      BAD_LINE=$n
      return 3
    fi
  done <"$1" >"$2"
}

# Number of op:// references outside comment lines.
reference_count() {
  awk '!/^[[:space:]]*#/ { n += gsub(/op:\/\/[^"'\''[:space:]]+/, "&") } END { print n + 0 }' "$1"
}

main() {
  module_start "$@"

  if [[ ! -d $SOURCE_DIR ]]; then
    log_skip "No $(tildify "$SOURCE_DIR")"
    module_finish
    return 0
  fi

  RENDER_DIR=$(mktemp -d "${TMPDIR:-/tmp}/omamas-secrets.XXXXXX")
  chmod 700 "$RENDER_DIR"
  add_exit_hook cleanup_render

  local src rel dst refs rendered rc unavailable=0
  while IFS= read -r -d '' src; do
    rel=${src#"$SOURCE_DIR"/}
    dst="$HOME/$rel"
    refs=$(reference_count "$src")

    if ((refs == 0)); then
      log_skip "$(tildify "$dst"): no secret references yet"
      continue
    fi
    if is_dry_run; then
      log_dry "render $(tildify "$dst") from 1Password ($refs references)"
      continue
    fi
    if ((unavailable)); then
      continue
    fi
    if ! has_cmd op; then
      log_warn "1Password CLI (op) not installed; skipping secrets"
      unavailable=1
      continue
    fi

    rendered="$RENDER_DIR/${rel//\//_}"
    # op's own errors name references, never values.
    rc=0
    if is_shell_file "$src"; then
      render_shell "$src" "$rendered" || rc=$?
    else
      run_with_timeout "$TIMEOUT" op inject --force --in-file "$src" --out-file "$rendered" >/dev/null || rc=$?
    fi
    if ((rc == 3)); then
      # Never echo the line itself: it may be a value pasted by mistake.
      log_error "$(tildify "$src") line $BAD_LINE: only comments and export NAME=\"op://…\" are allowed; not rendered"
      continue
    elif ((rc == 142)); then
      log_warn "1Password didn't answer within ${TIMEOUT}s (approval prompt unanswered?)"
      unavailable=1
      continue
    elif ((rc != 0)); then
      log_warn "Couldn't read secrets from 1Password for $(tildify "$dst")"
      unavailable=1
      continue
    fi
    chmod 600 "$rendered"

    if [[ -f $dst ]] && cmp -s "$rendered" "$dst"; then
      log_skip "$(tildify "$dst") ($refs secrets, unchanged)"
      continue
    fi
    if [[ -e $dst || -L $dst ]]; then
      backup_path "$dst" || continue
    fi
    if mkdir -p "$(dirname "$dst")" && install -m 600 "$rendered" "$dst"; then
      log_success "Rendered $(tildify "$dst") ($refs secrets)"
    else
      log_error "Could not write $(tildify "$dst")"
    fi
  done < <(find "$SOURCE_DIR" -type f ! -name .DS_Store -print0 | sort -z)

  if ((unavailable)); then
    add_note "Secrets not rendered: turn on 1Password → Settings → Developer → \"Integrate with 1Password CLI\", then: ./setup.sh --only secrets"
  fi
  module_finish
}

main "$@"
