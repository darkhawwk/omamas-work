#!/usr/bin/env bash
# capture.sh — Draft configs/ from the current Mac, for you to review.
#
# Read-only: inspects Homebrew, your home directory and macOS preferences, and
# writes drafts to drafts/<run-id>/ (git-ignored). It never modifies configs/,
# your dotfiles or any preference. Adopt what you want by hand, then commit.
#
# Usage: ./capture.sh [options]
#   -o, --only PART   Capture only PART: brew, dotfiles or defaults (repeatable).
#       --out DIR     Write drafts to DIR instead of drafts/<run-id>/.
#   -h, --help        Show this help.
#
# Environment:
#   OMAMAS_CAPTURE_DOMAINS   Space-separated preference domains to inspect
#                            (default: a curated list of common macOS domains).

# shellcheck source=scripts/utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/scripts/utils.sh"

# Homebrew must not auto-update itself: that would make capture a write.
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1

PARTS=()
OUT=""

DEFAULT_DOMAINS="NSGlobalDomain com.apple.dock com.apple.finder com.apple.screencapture
  com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad
  com.apple.AppleMultitouchMouse com.apple.driver.AppleBluetoothMultitouch.mouse
  com.apple.menuextra.clock com.apple.WindowManager com.apple.spaces com.apple.desktopservices
  com.apple.screensaver com.apple.TextEdit com.apple.ActivityMonitor com.apple.Terminal"

# Preference keys that record state rather than choices. KB_*Option are only the
# labels System Settings shows; the real quote setting is NSUserQuotesArray.
NOISE_KEYS='^(mod-count|loc|region|trash-full|version|AK.*|PK.*|NSLinguistic.*|NSWindow.*|NSSplitView.*|NSTableView.*|NSToolbar.*|NSNavPanel.*|NSStatusItem.*|KB_.*Option|FXRecentFolders|FXConnectToLastURL|GoToField.*)$|[Ll]ast|(^|[^p])[Dd]ate|[Tt]ime[Ss]tamp|[Vv]ersion|UUID|[Aa]nalytics|[Cc]ache|[Ww]indow|[Ss]tate$|[Cc]ount$|Upgraded|TransitionComplete|EverEdited|SerialNumber|^FXICloud|^FXDetached|Width|Height|ExpandedState'

HAS_SPACE='[[:space:]]'
EDGE_SPACE='^[[:space:]]|[[:space:]]$'

# Top-level home entries that are history, caches or tool-managed installs.
NOISE_HOME=' .DS_Store .CFUserTextEncoding .Trash .cache .local .cups .zsh_history .bash_history
  .zsh_sessions .bash_sessions .lesshst .viminfo .python_history .node_repl_history .wget-hsts
  .sqlite_history .psql_history .mysql_history .rediscli_history .irb_history .Xauthority .npm
  .cargo .rustup .gem .bundle .cocoapods .gradle .m2 .nvm .pyenv .rbenv .volta .bun .deno .yarn
  .pnpm-store .android .dartServer .dotnet .swiftpm .vscode .cursor .colima .lima .orbstack '

# Paths that hold credentials: restore them from a password manager, not git.
SECRET_HOME=' .ssh .gnupg .aws .netrc .pgpass .docker .kube .password-store .azure .gcloud '

# Collapse the lists onto one line so " name " matching works for every entry.
# shellcheck disable=SC2116,SC2086
NOISE_HOME=" $(echo $NOISE_HOME) "

# Editor/backup leftovers are never worth adopting.
BACKUP_NAME='(\.bak|\.backup|\.old|\.orig|\.swp|~)(\.[0-9]+)?$|\.bak\.'

# Above this size a "dotfile" is almost always written by an app, not by you.
MAX_DOTFILE_BYTES=32768

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -o | --only)
        case ${2:-} in brew | dotfiles | defaults) PARTS+=("$2") ;; *) die "--only takes brew, dotfiles or defaults" ;; esac
        shift
        ;;
      --out) OUT=${2:?--out needs a directory}; shift ;;
      -h | --help) __omamas_usage "$0"; exit 0 ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  ((${#PARTS[@]} > 0)) || PARTS=(brew dotfiles defaults)
}

wants() {
  local p
  for p in "${PARTS[@]}"; do [[ $p == "$1" ]] && return 0; done
  return 1
}

human_size() {
  awk -v b="$1" 'BEGIN { split("B KB MB GB", u); i = 1; while (b >= 1024 && i < 4) { b /= 1024; i++ } printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i] }'
}

# ─── Brewfile ─────────────────────────────────────────────────────────────────
capture_brew() {
  log_step "Homebrew"
  if ! ensure_brew_shellenv; then
    log_warn "Homebrew not installed; skipping Brewfile"
    return 0
  fi
  local dest="$OUT/Brewfile" body
  if ! body=$(brew bundle dump --file=- 2>/dev/null); then
    log_error "brew bundle dump failed"
    return 0
  fi
  # The dump can list Go's own tools (e.g. `go "cmd/go"` when Go comes from
  # mise or similar). `go install` rejects standard-library paths, which are
  # the ones without a dot in their first element.
  local stdlib='^go "[^"./]+[/"]' dropped
  dropped=$(printf '%s\n' "$body" | grep -cE "$stdlib" || true)
  if ((dropped > 0)); then
    body=$(printf '%s\n' "$body" | grep -vE "$stdlib")
    log_info "Dropped $dropped Go standard-library entries (not installable)"
  fi
  {
    echo "# Brewfile draft captured from $(scutil --get ComputerName 2>/dev/null || hostname) on $(date '+%Y-%m-%d')."
    echo "# Everything installed on request. Delete what you don't want on a new Mac."
    echo
    printf '%s\n' "$body"
  } >"$dest"
  local kind
  for kind in tap brew cask mas vscode go cargo uv npm; do
    local n
    n=$(grep -c "^$kind " "$dest" || true)
    ((n == 0)) || log_info "$n $kind entries"
  done
  log_success "Wrote $(tildify "$dest")"
}

# ─── Dotfiles ─────────────────────────────────────────────────────────────────
# Print the kinds of secret a file appears to contain (never the values).
secret_kinds() {
  local f=$1 kinds=""
  [[ -f $f && $(stat -f %z "$f") -lt 1048576 ]] || return 0
  grep -Iq . "$f" 2>/dev/null || return 0 # skip binary files
  grep -Eq -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$f" && kinds+="private key, "
  grep -Eq 'AKIA[0-9A-Z]{16}' "$f" && kinds+="AWS key, "
  grep -Eq 'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}' "$f" && kinds+="GitHub token, "
  grep -Eq 'sk-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}' "$f" && kinds+="API token, "
  grep -Eiq '(api[_-]?key|secret|token|passw(or)?d|auth)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[^[:space:]"'"'"'$]{8,}' "$f" &&
    kinds+="credential assignment, "
  printf '%s' "${kinds%, }"
}

# Shell command that copies ~/REL to configs/home/REL.
adopt_command() {
  local rel=$1 dir
  dir=$(dirname "$rel")
  if [[ $dir == . ]]; then
    printf 'cp -p ~/%q configs/home/%q\n' "$rel" "$rel"
  else
    printf 'mkdir -p configs/home/%q && cp -p ~/%q configs/home/%q\n' "$dir" "$rel" "$rel"
  fi
}

# Inspect one path and append a line to the matching report section.
classify() {
  local path=$1 name=${1##*/} shown kinds n size
  shown=$(tildify "$path")

  if [[ -L $path ]]; then
    case $(readlink "$path") in
      "$OMAMAS_CONFIG_DIR"/home/*) echo "- \`$shown\`" >>"$TMP/managed" ;;
      *) echo "- \`$shown\` → \`$(readlink "$path")\` (symlink managed elsewhere)" >>"$TMP/dirs" ;;
    esac
    return 0
  fi

  if [[ $SECRET_HOME == *" $name "* && $path == "$HOME/$name" ]]; then
    echo "- \`$shown\`" >>"$TMP/secrets"
    return 0
  fi

  if [[ $name =~ $BACKUP_NAME ]]; then
    printf '%s ' "$name" >>"$TMP/ignored"
    return 0
  fi

  if [[ -f $path ]]; then
    size=$(stat -f %z "$path")
    kinds=$(secret_kinds "$path")
    if [[ -n $kinds ]]; then
      echo "- \`$shown\` ($(human_size "$size")) — looks like it contains: $kinds" >>"$TMP/flagged"
    elif ((size > MAX_DOTFILE_BYTES)); then
      echo "- \`$shown\` ($(human_size "$size"))" >>"$TMP/appdata"
    else
      echo "- \`$shown\` ($(human_size "$size"))" >>"$TMP/candidates"
      adopt_command "${path#"$HOME"/}" >>"$TMP/adopt"
    fi
    return 0
  fi

  if [[ -d $path ]]; then
    # `|| true`: head exits early on big trees and find then dies of SIGPIPE,
    # which pipefail would otherwise turn into a fatal error.
    n=$( (find "$path" -type f 2>/dev/null || true) | head -n 1001 | wc -l | tr -d ' ')
    size=$(($(du -sk "$path" 2>/dev/null | cut -f1) * 1024))
    local note="" f flagged=""
    if ((n <= 50)); then
      while IFS= read -r -d '' f; do
        [[ -z $(secret_kinds "$f") ]] || flagged+="${f#"$path"/}, "
      done < <(find "$path" -type f -print0 2>/dev/null)
      [[ -z $flagged ]] || note=" — possible secrets in: ${flagged%, }"
    fi
    ((n <= 1000)) || n="1000+"
    if [[ $n == "1000+" ]] || ((size > 5242880)); then
      echo "- \`$shown/\` ($n files, $(human_size "$size"))$note" >>"$TMP/appdata"
    else
      echo "- \`$shown/\` ($n files, $(human_size "$size"))$note" >>"$TMP/dirs"
    fi
  fi
}

capture_dotfiles() {
  log_step "Dotfiles"
  local dest="$OUT/dotfiles.md" path name ignored=""
  : >"$TMP/candidates"
  : >"$TMP/flagged"
  : >"$TMP/managed"
  : >"$TMP/dirs"
  : >"$TMP/secrets"
  : >"$TMP/adopt"
  : >"$TMP/appdata"
  : >"$TMP/ignored"

  for path in "$HOME"/.[!.]*; do
    [[ -e $path || -L $path ]] || continue
    name=${path##*/}
    case $name in .zcompdump*) ignored+="$name " && continue ;; esac
    if [[ $NOISE_HOME == *" $name "* ]]; then
      ignored+="$name "
      continue
    fi
    if [[ $name == .config && -d $path && ! -L $path ]]; then
      local entry
      for entry in "$path"/* "$path"/.[!.]*; do
        [[ -e $entry || -L $entry ]] && classify "$entry"
      done
      continue
    fi
    classify "$path"
  done

  section() { # title file intro
    local count
    count=$(grep -c . "$2" || true)
    ((count > 0)) || return 0
    printf '## %s (%d)\n\n' "$1" "$count"
    [[ -z ${3:-} ]] || printf '%s\n\n' "$3"
    cat "$2"
    echo
  }

  {
    echo "# Dotfile candidates — $(date '+%Y-%m-%d')"
    echo
    echo "Adopt a file by copying it to the same path under \`configs/home/\`. The next"
    echo "\`./setup.sh --only dotfiles\` backs up the original and replaces it with a link."
    echo
    section "Candidates" "$TMP/candidates" "Small text files with no obvious secrets."
    section "Review for secrets first" "$TMP/flagged" \
      "These match credential patterns (values are not shown). Move the secret out (e.g. into a password manager or an untracked \`~/.zshrc.local\`) before adopting."
    section "Config directories" "$TMP/dirs" \
      "Adopt individual files rather than whole directories, so apps can keep writing their own state."
    section "App data — usually not worth versioning" "$TMP/appdata" \
      "Large files and directories written by apps (caches, models, sessions). Back these up separately if you need them."
    section "Already managed by Omamas" "$TMP/managed"
    section "Credentials — keep out of git" "$TMP/secrets" \
      "Restore these from a password manager or backup, never from this repo."
    ignored+=$(cat "$TMP/ignored")
    if [[ -n $ignored ]]; then
      printf '## Ignored\n\nHistory, caches and tool-managed installs: %s\n\n' "$(printf '%s' "$ignored" | sed 's/ *$//; s/ /, /g')"
    fi
    if [[ -s $TMP/adopt ]]; then
      echo "## Adopt all candidates"
      echo
      echo "Run from the repo root after pruning the list:"
      echo
      echo '```bash'
      cat "$TMP/adopt"
      echo '```'
    fi
  } >"$dest"

  log_info "$(grep -c . "$TMP/candidates" || true) candidates, $(grep -c . "$TMP/flagged" || true) need a secrets review, $(grep -c . "$TMP/dirs" || true) config dirs, $(grep -c . "$TMP/appdata" || true) app data"
  log_success "Wrote $(tildify "$dest")"
}

# ─── macOS preferences ────────────────────────────────────────────────────────
# Emit "key<TAB>type<TAB>value" for each top-level scalar in a plist (XML on stdin).
plist_scalars() {
  awk '
    function unescape(s) {
      gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s)
      gsub(/&apos;/, "\047", s); gsub(/&amp;/, "\\&", s); return s
    }
    function inner(s) { sub(/^[^>]*>/, "", s); sub(/<\/[a-z]+>[[:space:]]*$/, "", s); return s }
    /^[[:space:]]*<(dict|array)>[[:space:]]*$/ { depth++; key = ""; next }
    /^[[:space:]]*<\/(dict|array)>[[:space:]]*$/ { depth--; key = ""; next }
    depth != 1 { next }
    /^[[:space:]]*<key>.*<\/key>[[:space:]]*$/ { key = unescape(inner($0)); next }
    key == "" { next }
    /<true\/>/ { print key "\t-bool\ttrue" }
    /<false\/>/ { print key "\t-bool\tfalse" }
    /<integer>.*<\/integer>/ { print key "\t-int\t" inner($0) }
    /<real>.*<\/real>/ { v = inner($0) + 0; print key "\t-float\t" sprintf("%.7g", v) }
    /<string>.*<\/string>/ { print key "\t-string\t" unescape(inner($0)) }
    { key = "" }
  '
}

capture_defaults() {
  log_step "macOS preferences"
  local dest="$OUT/macos/defaults.conf" domains=${OMAMAS_CAPTURE_DOMAINS:-$DEFAULT_DOMAINS}
  local domain xml key type value total=0 unreadable=""
  mkdir -p "$OUT/macos"
  {
    echo "# defaults.conf draft captured on $(date '+%Y-%m-%d')."
    echo "# Keys explicitly set in each domain (macOS keeps no record of factory"
    echo "# defaults, so some of these may simply be values the system wrote)."
    echo "# Keep the lines that express a preference; delete the rest."
    echo "# Collections (arrays/dicts) and keys with spaces are not captured."
  } >"$dest"

  for domain in $domains; do
    if ! xml=$(defaults export "$domain" - 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null); then
      unreadable+="$domain "
      continue
    fi
    local lines=""
    while IFS=$'\t' read -r key type value; do
      if [[ -z $value || $key =~ $HAS_SPACE || $value =~ $EDGE_SPACE || $key =~ $NOISE_KEYS ]]; then
        continue
      fi
      [[ $type == -string && $value == "$HOME"* ]] && value="~${value#"$HOME"}"
      lines+=$(printf '%-48s %-44s %-8s %s' "$domain" "$key" "$type" "$value")$'\n'
      total=$((total + 1))
    done < <(printf '%s\n' "$xml" | plist_scalars)
    [[ -n $lines ]] && printf '\n# ── %s\n%s' "$domain" "$lines" >>"$dest"
  done

  [[ -z $unreadable ]] || log_warn "Could not read: $unreadable(missing, or needs Full Disk Access)"
  log_info "$total settings across $(grep -c '^# ── ' "$dest" || true) domains"
  log_success "Wrote $(tildify "$dest")"
}

# ─── Review summary ───────────────────────────────────────────────────────────
write_review() {
  local rel=${OUT#"$OMAMAS_ROOT"/}
  {
    echo "# Capture $OMAMAS_RUN_ID"
    echo
    echo "Drafts generated from this Mac by \`./capture.sh\`. Nothing here is applied"
    echo "until you copy it into \`configs/\`."
    echo
    [[ ! -f $OUT/Brewfile ]] || echo "- \`Brewfile\`: \`diff -u configs/Brewfile $rel/Brewfile\`, prune, then copy over."
    [[ ! -f $OUT/dotfiles.md ]] || echo "- \`dotfiles.md\`: candidates, secret warnings and copy commands for \`configs/home/\`."
    [[ ! -f $OUT/macos/defaults.conf ]] || echo "- \`macos/defaults.conf\`: keep the lines you care about in \`configs/macos/defaults.conf\`."
    echo
    echo "Then preview with \`./setup.sh --dry-run\` before applying."
  } >"$OUT/REVIEW.md"
}

main() {
  parse_args "$@"
  require_macos
  OUT=${OUT:-$OMAMAS_ROOT/drafts/$OMAMAS_RUN_ID}
  mkdir -p "$OUT"
  OUT=$(cd -P "$OUT" && pwd)
  TMP=$(mktemp -d -t omamas-capture)
  add_exit_hook cleanup_tmp

  log_info "Capturing this Mac into $(tildify "$OUT") (read-only)"
  if wants brew; then capture_brew; fi
  if wants dotfiles; then capture_dotfiles; fi
  if wants defaults; then capture_defaults; fi
  write_review

  echo
  log_info "Review: $(tildify "$OUT/REVIEW.md")"
}

cleanup_tmp() { rm -rf "${TMP:-}"; }

main "$@"
