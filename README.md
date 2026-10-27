<p align="center">
  <img src="assets/logo.png" alt="Omamas logo: a terminal prompt and cursor inside a blue-to-violet ring" width="160">
</p>

# Omamas

*お任せ + macOS.* You leave the machine to it: one command turns a factory-reset Mac into your development environment. Running it again on a Mac you already use reconciles that machine back to the declared state, changing only what has drifted.

```bash
curl -fsSL https://raw.githubusercontent.com/thebenwalther/omamas/main/install.sh | bash
```

Pass flags through with `bash -s --`, e.g. `... | bash -s -- --dry-run`.

## Layout

```
omamas/
├── install.sh                 Orchestration · remote bootstrap (curl | bash)
├── setup.sh                   Orchestration · local runner: pre-flight, log, sudo, modules
├── capture.sh                 Read-only: drafts configs/ from the current Mac into drafts/
├── configs/                   State · what should exist. No logic.
│   ├── Brewfile                 formulae, casks, taps, mas apps
│   ├── directories.conf         directories + modes
│   ├── home/                    mirror of $HOME; every file is symlinked into place
│   ├── fonts/                   .ttf/.otf/.ttc copied to ~/Library/Fonts
│   └── macos/defaults.conf      `defaults` preferences
├── scripts/                   Imperative · how to get there
│   ├── utils.sh                 shared runtime (sourced): logging, traps, run, sudo, backups
│   ├── symlink.sh               shared library (sourced): link_file, prune_stale_links
│   ├── _template.sh             copy to start a new module
│   ├── 05-sudo-touchid.sh       ┐
│   ├── 10-homebrew.sh           │
│   ├── 20-packages.sh           │ modules: run in numeric order by setup.sh,
│   ├── 30-directories.sh        │ each one also runs standalone
│   ├── 40-dotfiles.sh           │
│   ├── 50-fonts.sh              │
│   └── 60-macos-defaults.sh     ┘
├── assets/logo.png            Project logo
├── tests/                     Sandboxed tests (fake $HOME; never touch the real machine)
└── .github/workflows/ci.yml   Lint + tests, then a real bootstrap on an ephemeral macOS VM
```

**Tier rules**

- `configs/` holds data only. If you're tempted to write an `if` there, put it in a module. (`Brewfile` is technically Ruby; keep it to one declaration per line.)
- `scripts/` holds logic and never hardcodes what gets installed. Each module reads its own manifest.
- The root scripts only sequence work. `setup.sh` never imports a module; it runs each one as a separate process (`"$BASH" scripts/NN-x.sh`), so a module behaves the same whether `setup.sh` runs it or you run it by hand.

## How a run works

`install.sh`
1. Checks it is on macOS and not running as root.
2. Installs the Xcode Command Line Tools: headless through `softwareupdate`, falling back to Apple's GUI installer.
3. Clones the repo to `~/.local/share/omamas` (`OMAMAS_DIR`), or fast-forwards an existing clone that has no local changes.
4. Hands off with `exec setup.sh "$@"`, reattaching stdin to the terminal so prompts work under `curl | bash`.

The whole script sits inside `main`, which is called on the last line, so a truncated download can't run a partial script.

`setup.sh`
1. Takes a lock (`~/.local/state/omamas/setup.lock`) so two runs can't overlap.
2. Mirrors all output to `~/.local/state/omamas/logs/setup-<run-id>.log` with ANSI colors stripped. `latest.log` always points at the newest log.
3. Pre-flight: macOS ≥ `OMAMAS_MIN_MACOS` (default 14.0), not root, configs present, network reachable, disk space.
4. Runs `sudo -v` once, but only if a selected module carries `# omamas: requires-sudo`. A background keep-alive then holds the sudo ticket until the run exits. `caffeinate` keeps the Mac awake. On a fresh Mac this is the only password prompt: `05-sudo-touchid` runs first and switches sudo to Touch ID (see below).
5. Runs each module and records ok / FAILED and how long it took. A failing module doesn't stop the run unless you pass `--fail-fast`.
6. Prints a summary, any follow-up notes (e.g. "log out to apply"), the log path and the backup path. The exit status is non-zero if any module failed.

```
./setup.sh [-n|--dry-run] [-o|--only NAME]... [-s|--skip NAME]... [-l|--list] [--fail-fast] [--upgrade]
```

## Guarantees

| Principle | Mechanism |
|---|---|
| **Idempotency** | Every item is checked before anything is done to it: it's either already right (`[SKIP]`) or gets changed (`[SUCCESS]`). Each module ends with `name: N changed, M unchanged`; CI fails if a second run reports anything changed. |
| **Non-destructive** | Before a file is replaced, `backup_path` moves it to `~/.local/state/omamas/backups/<run-id>/<path relative to $HOME>`. A collision gets `.1`, `.2`, …, so a backup is never overwritten. Nothing is ever `rm`'d except symlinks that Omamas itself created. |
| **Declarative removal** | `40-dotfiles` records the links it owns in `links.tsv`. On the next run, a link whose source was deleted from `configs/home/` is removed, but only if it still points at exactly that source. `20-packages` never uninstalls anything; it only reports packages that are installed but not declared (**drift**). |
| **Dry run** | `--dry-run` (or `-n` on any module) sends every change through `run` / `log_dry` and changes nothing. |
| **Fail-safe** | `set -Eeuo pipefail`. The ERR trap reports the failing command with its file and line, EXIT hooks clean up (keep-alive, lock, temp files), and Ctrl-C exits 130. |
| **Telemetry** | `[INFO] [SKIP] [SUCCESS] [WARN] [ERROR] [DRY]`, timestamped and colored. Color is turned off when output isn't a terminal or `NO_COLOR` is set. |

To restore from a backup, copy it back over your home directory. The backup tree mirrors `$HOME`:

```bash
cp -a ~/.local/state/omamas/backups/<run-id>/. ~/
```

## Manifests

| File | Format | Module |
|---|---|---|
| `configs/Brewfile` | `brew "x"`, `cask "y"`, `tap "a/b"`, `mas "App", id: N` | `20-packages` |
| `configs/directories.conf` | `<path> [octal-mode]` | `30-directories` |
| `configs/home/**` | file at `configs/home/P` → symlink at `~/P` | `40-dotfiles` |
| `configs/fonts/*` | font files | `50-fonts` |
| `configs/macos/defaults.conf` | `<domain> <key> <-bool\|-int\|-float\|-string> <value…>` | `60-macos-defaults` |

In the `.conf` files, lines starting with `#` and blank lines are ignored, and a leading `~` expands to `$HOME`. Every manifest ships with its examples commented out, so a fresh clone changes nothing until you declare something.

Dotfiles are linked **file by file**, never as whole directories. That lets apps write their own state next to your managed files, and it keeps app-generated files out of the repo. Because symlinks point into the clone, keep the clone in a stable location.

## Capturing an existing Mac

`./capture.sh` gives you a first draft of `configs/` from the Mac you're on. It's read-only: it never touches `configs/`, your dotfiles or any preference, and it runs Homebrew with auto-update off. Everything it produces goes to `drafts/<run-id>/`, which is git-ignored:

| Draft | Source | What it gives you |
|---|---|---|
| `Brewfile` | `brew bundle dump` | Every tap, formula, cask, App Store app and language package you installed on request, with descriptions |
| `dotfiles.md` | scan of `~` and `~/.config` | A report sorted into: adoption candidates, files that look like they hold secrets, config directories, app data, credentials, and noise it ignored. Ends with `cp` commands for the clean candidates |
| `macos/defaults.conf` | `defaults export` on common domains | Explicitly set scalar keys with their real types, minus bookkeeping keys. `$HOME` paths are rewritten as `~` so they work under another username |

macOS keeps no record of factory defaults, so the preferences draft lists keys that are *set*, not keys that were *changed*. Keep the lines that express a choice. The secret scan reports only the kind of match (e.g. "GitHub token"), never the value.

```bash
./capture.sh                                   # or: --only brew|dotfiles|defaults
diff -u configs/Brewfile drafts/*/Brewfile     # prune, then copy over
OMAMAS_CAPTURE_DOMAINS="com.apple.dock com.googlecode.iterm2" ./capture.sh --only defaults
./setup.sh --dry-run                           # after adopting: should report ~0 pending on this Mac
```

## Touch ID for sudo

`05-sudo-touchid` copies Apple's `/etc/pam.d/sudo_local.template` to `sudo_local` with the `pam_tid.so` line uncommented (macOS 14+). Unlike edits to `/etc/pam.d/sudo`, `sudo_local` survives OS updates.

- **When it pays off.** During a run the sudo keep-alive already avoids repeat prompts. The win is any prompt after the ticket lapses, every future `./setup.sh` run, and everyday `sudo`.
- **Fallback.** The password still works whenever Touch ID can't: no finger enrolled yet, lid closed on an external display, or an SSH session.
- **Safety.** The module only ever adds that one line. Other lines in an existing `sudo_local` are kept, and the old file is copied to the backup directory. Before installing, it checks that the new file differs from the old one only by that line. It writes a staged file and renames it into place, so sudo never reads a half-written file.
- **tmux / screen.** Touch ID doesn't work inside them without `pam_reattach`. Add `brew "pam-reattach"` to the Brewfile and put `auth optional /opt/homebrew/lib/pam/pam_reattach.so ignore_ssh` at the top of `sudo_local`. The module appends `pam_tid` after existing lines, so the order stays correct.
- **Opt out / undo.** Skip it with `--skip sudo-touchid`. Undo it with `sudo rm /etc/pam.d/sudo_local`.

## Adding a module

```bash
cp scripts/_template.sh scripts/70-runtimes.sh   # the number decides the order
$EDITOR scripts/70-runtimes.sh configs/runtimes.conf
scripts/70-runtimes.sh --dry-run
```

The module contract, which `_template.sh` spells out:
1. **Standalone.** The module sources `utils.sh` itself and checks its own prerequisites (`ensure_brew_shellenv || die ...`) instead of assuming earlier modules ran.
2. **Check, then act.** Each item is either `log_skip` or changed and then `log_success`.
3. **Data comes from `configs/`.** Read manifests with `read_manifest`.
4. **Mutations go through `run`,** or an explicit `is_dry_run` branch.
5. **Per-item failures** go to `log_error` and the loop continues. `module_finish` turns any errors into a non-zero exit at the end.
6. If the module may need admin rights, add a `# omamas: requires-sudo` line.

Only files named `NN-*.sh` are modules. Everything else in `scripts/` is a library or the template.

**Bash 3.2.** A factory-fresh Mac only has `/bin/bash` 3.2, so every script must run on it. That means:
- no associative arrays, `mapfile`, or `${x,,}`
- expand arrays that might be empty as `${a[@]+"${a[@]}"}`
- increment counters with `n=$((n+1))`, not `((n++))`, which returns 1 when `n` is 0 and kills the script under `set -e`
- inside a function that is called from `if` or `||`, `set -e` is switched off, so check every step explicitly (as `link_file` does)
- never write `x=$(cond && echo y)`, which fails under `set -e` when `cond` is false; use `dry_label`-style helpers instead

## Testing, from least to most invasive

1. **Unit tests in a sandbox.** These run against a fake `$HOME` and fixture configs. The `defaults` tests use plist *file paths* as domains, so your real preferences are never read or written.
   ```bash
   tests/run.sh
   ```
   This also runs `bash -n` on every script, and ShellCheck if it's installed (`brew install shellcheck`).

2. **One module, standalone, in a throwaway home.** Point `HOME` and `OMAMAS_CONFIG_DIR` at scratch directories:
   ```bash
   export SANDBOX=$(mktemp -d); mkdir -p "$SANDBOX/home" "$SANDBOX/configs/home"
   echo 'echo hi' > "$SANDBOX/configs/home/.zshrc"
   HOME="$SANDBOX/home" OMAMAS_CONFIG_DIR="$SANDBOX/configs" scripts/40-dotfiles.sh
   HOME="$SANDBOX/home" OMAMAS_CONFIG_DIR="$SANDBOX/configs" scripts/40-dotfiles.sh   # expect "0 changed"
   ls -la "$SANDBOX/home"
   ```
   macOS preferences aren't scoped by `$HOME`, so test `60-macos-defaults` with `--dry-run` or through `tests/test_defaults.sh`.

3. **Dry run on your real machine.** This reads real state and writes nothing except a log:
   ```bash
   ./setup.sh --dry-run
   ./setup.sh --dry-run --only dotfiles
   ```

4. **Real run, one module at a time:** `./setup.sh --only directories`, then dotfiles, and so on. Check `~/.local/state/omamas/backups/` after each one. Running the same command again must report `0 changed`.

5. **End to end on a clean Mac.**
   - Run the bootstrap in a disposable macOS VM, using [Tart](https://tart.run) or UTM on Apple silicon. Snapshot the fresh install, run the `curl | bash` one-liner, run `./setup.sh` a second time, then revert to the snapshot.
   - CI does the same on every push: `.github/workflows/ci.yml` bootstraps through `install.sh` on an ephemeral `macos-latest` runner and fails if the second run changes anything.

To test `install.sh` against a local branch without pushing:
```bash
cat install.sh | OMAMAS_REPO="file://$PWD" OMAMAS_REF=$(git branch --show-current) OMAMAS_DIR=/tmp/omamas-try bash -s -- --dry-run
```

## Environment variables

| Variable | Effect |
|---|---|
| `OMAMAS_DIR` / `OMAMAS_REPO` / `OMAMAS_REF` | Where `install.sh` clones the repo, from which URL, and which branch |
| `OMAMAS_CONFIG_DIR` | Use a different State tier (handy for sandboxes and per-machine profiles) |
| `OMAMAS_UPGRADE=1` | Also `brew update` and upgrade outdated packages (same as `--upgrade`) |
| `OMAMAS_CAPTURE_DOMAINS` | Preference domains `capture.sh` inspects (default: a curated list of macOS domains) |
| `OMAMAS_PAM_DIR` | Use a different PAM directory than `/etc/pam.d` (used by the tests) |
| `OMAMAS_NO_RESTART=1` | Don't quit or restart Dock, Finder or System Settings; add a follow-up note instead |
| `OMAMAS_MIN_MACOS` | Minimum macOS version allowed by pre-flight (default `14.0`) |
| `OMAMAS_DRY_RUN=1` | Same as `--dry-run` |
| `NO_COLOR` | Plain output |
