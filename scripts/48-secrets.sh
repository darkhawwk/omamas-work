#!/usr/bin/env bash
# 48-secrets.sh — Render secret files from 1Password references.
#
# Every file under configs/secrets/ is a template for the same path under
# $HOME (configs/secrets/.zshrc.local → ~/.zshrc.local). Templates contain
# op://<vault>/<item>/<field> references, never values; `op inject` fills them
# in and the result is written with mode 600. Values never enter git, logs or
# backups' names; only "changed" or "unchanged" is reported.
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
    run_with_timeout "$TIMEOUT" op inject --force --in-file "$src" --out-file "$rendered" >/dev/null || rc=$?
    if ((rc == 142)); then
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
