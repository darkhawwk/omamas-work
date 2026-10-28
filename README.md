<p align="center">
  <img src="assets/logo.png" alt="Omamas logo: a terminal prompt and cursor inside a blue-to-violet ring" width="160">
</p>

# Omamas

*お任せ + macOS.* You leave the machine to it: one command turns a factory-reset Mac into your development environment. Running it again on a Mac you already use reconciles that machine back to the declared state, changing only what has drifted.

```bash
curl -fsSL https://raw.githubusercontent.com/thebenwalther/omamas/main/install.sh | bash
```

Pass flags through with `bash -s --`, e.g. `... | bash -s -- --dry-run`.

## New Mac checklist

Nothing has to be installed first: `install.sh` brings the Xcode Command Line Tools (and git), and the modules install Rosetta 2, Homebrew and everything else.

### Before you run it

- [ ] **On the old Mac: back up Claude.** Quit Claude, then run `migrate/claude-backup.sh` from Terminal (see [Moving Claude data between Macs](#moving-claude-data-between-macs)). It also lists repos with uncommitted or unpushed work; push those now.
- [ ] **macOS 14 (Sonoma) or newer**, set up through Setup Assistant with an **admin** account. Run Omamas as that user, not with `sudo`.
- [ ] **Connected to the internet.**
- [ ] **Touch ID fingerprint enrolled** (System Settings → Touch ID & Password), so `sudo` can use it after the first prompt. Without one, sudo falls back to your password.
- [ ] **Signed into the App Store** with the Apple ID that owns your `mas` apps. Nothing can sign in for you. If you forget, those apps are skipped with a follow-up note; sign in, then run `./setup.sh --only packages`.
- [ ] **Decide where the repo lives.** Dotfile symlinks point into the checkout, which defaults to `~/.local/share/omamas`. To mirror this Mac, set `OMAMAS_DIR`:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/thebenwalther/omamas/main/install.sh | OMAMAS_DIR=~/Work/github.com/thebenwalther/omamas bash
  ```
- [ ] **Same username as the old Mac** (`el-kal`) if you'll restore Claude sessions; they're filed by path.
- [ ] **Plugged in**, if it's a laptop. `caffeinate` keeps it awake, but downloading every cask takes a while.

### While it runs: stay nearby for the first few minutes

- [ ] **Your password, once.** From then on Touch ID works.
- [ ] **Command Line Tools dialog.** Only appears if the silent install isn't available; click Install and the script waits.
- [ ] **"Terminal wants to control System Settings"**: allow it. The preferences step closes System Settings so it can't overwrite new values.
- [ ] **"Terminal wants to control System Events"**: allow it, so your login items can be added.
- [ ] **"Do you want to change your default web browser?"**: choose Brave.
- [ ] **Sign in to 1Password when it opens.** It's installed right after Homebrew and opened for you; the run doesn't wait, so sign in while packages install.
- [ ] **Cask installer prompts.** Some apps ask for a password or permission mid-install.

After that the run is unattended. The summary lists failed modules, follow-ups (e.g. log out for global preferences), the log file and the backup folder. Re-running is always safe and only retries what isn't done yet.

### After it finishes

- [ ] **Open a new terminal**, so the new shell config loads.
- [ ] **Log out and back in** if the summary asks; some global preferences only apply then.
- [ ] **Turn on 1Password's SSH agent** (Settings → Developer). `~/.ssh/config` already points at it, so git over SSH works from then on. If 1Password asks to approve an app's use of a key, approve it.
- [ ] **Clone the private repos:** if the summary listed repos it couldn't clone yet (no SSH access during the first run), run `./setup.sh --only repos` now.
- [ ] **Turn on 1Password's CLI integration** (Settings → Developer → "Integrate with 1Password CLI"), then `./setup.sh --only secrets` if the summary said secrets weren't rendered.
- [ ] **Sign into apps** and enter licenses: Dropbox, Slack, Zoom, Notion and the rest.
- [ ] **Grant privacy permissions** as apps ask: Accessibility, Screen Recording, Full Disk Access.
- [ ] **Restore Claude:** quit Claude if it's open, wait for iCloud Drive to sync, then run `migrate/claude-restore.sh` and open Claude to sign in. Sessions resume because `45-repos` cloned your repos to their old paths.
- [ ] **Confirm it converged:** `./setup.sh` again should report `0 changed` for every module.

## Layout

```
omamas/
├── install.sh                 Orchestration · remote bootstrap (curl | bash)
├── setup.sh                   Orchestration · local runner: pre-flight, log, sudo, modules
├── capture.sh                 Read-only: drafts configs/ from the current Mac into drafts/
├── migrate/                   Claude data between Macs (not part of setup.sh)
│   ├── claude-backup.sh         encrypted image of local Claude data → iCloud Drive
│   └── claude-restore.sh        restore it on the new Mac
├── configs/                   State · what should exist. No logic.
│   ├── Brewfile                 formulae, casks, taps, mas apps
│   ├── claude-backup.conf       where Claude backups go; which folder to check for repos
│   ├── drift-check.conf         when the weekly drift check runs
│   ├── directories.conf         directories + modes
│   ├── home/                    mirror of $HOME; every file is symlinked into place
│   ├── fonts/                   .ttf/.otf/.ttc copied to ~/Library/Fonts
│   ├── macos/computer-name.conf this Mac's name
│   ├── repos.conf               git repos to clone under ~/Work
│   ├── secrets/                 templates with op:// references, rendered into $HOME
│   ├── macos/defaults.conf      `defaults` preferences
│   ├── macos/dock.conf          Dock apps, in order
│   ├── macos/default-apps.conf  which app opens which links and documents
│   ├── macos/login-items.conf   apps that open at login
│   └── macos/security.conf      firewall, stealth mode, FileVault check
├── scripts/                   Imperative · how to get there
│   ├── utils.sh                 shared runtime (sourced): logging, traps, run, sudo, backups
│   ├── symlink.sh               shared library (sourced): link_file, prune_stale_links
│   ├── _template.sh             copy to start a new module
│   ├── 02-computer-name.sh      ┐
│   ├── 05-sudo-touchid.sh       │
│   ├── 07-rosetta.sh            │
│   ├── 10-homebrew.sh           │
│   ├── 15-1password.sh          │
│   ├── 17-security.sh           │
│   ├── 20-packages.sh           │ modules: run in numeric order by setup.sh,
│   ├── 30-directories.sh        │ each one also runs standalone
│   ├── 40-dotfiles.sh           │
│   ├── 45-repos.sh              │
│   ├── 47-runtimes.sh           │
│   ├── 48-secrets.sh            │
│   ├── 50-fonts.sh              │
│   ├── 60-macos-defaults.sh     │
│   ├── 62-dock.sh               │
│   ├── 64-default-apps.sh       │
│   ├── 66-login-items.sh        │
│   ├── 70-drift-check.sh        ┘
│   └── drift-check.sh           weekly "still in sync?" report (run by the LaunchAgent)
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
4. Runs `sudo -v` once, but only if a selected module carries `# omamas: requires-sudo`. A background keep-alive then holds the sudo ticket until the last such module (`20-packages`) finishes, then drops it with `sudo -k`. `caffeinate` keeps the Mac awake. On a fresh Mac this is the only password prompt: `05-sudo-touchid` runs first and switches sudo to Touch ID (see below).
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
| `configs/home/.config/mise/config.toml` | mise `[tools]` table, e.g. `node = "lts"` | `47-runtimes` (linked by `40-dotfiles`) |
| `configs/repos.conf` | `<host>/<owner>/<repo>`, cloned to `~/Work/<host>/<owner>/<repo>` | `45-repos` |
| `configs/fonts/*` | font files | `50-fonts` |
| `configs/macos/defaults.conf` | `<domain> <key> <-bool\|-int\|-float\|-string> <value…>` | `60-macos-defaults` |
| `configs/macos/dock.conf` | one app path per line, in Dock order | `62-dock` |
| `configs/macos/default-apps.conf` | `<bundle-id> <url-scheme>` or `<bundle-id> <type-id> <role>` | `64-default-apps` |
| `configs/macos/login-items.conf` | `<app path> [hidden]` | `66-login-items` |
| `configs/macos/security.conf` | `firewall on\|off`, `stealth on\|off`, `filevault check` | `17-security` |

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

## Repos

`45-repos.sh` clones each repo in `configs/repos.conf` that isn't checked out yet, to the same path it has on this Mac: `github.com/thebenwalther/pipeline` → `~/Work/github.com/thebenwalther/pipeline`. Existing checkouts are never fetched, pulled or changed, so it's safe on a Mac you're working on.

- **Access:** it tries SSH first (1Password's agent), then HTTPS with your `gh auth login` if you have one, then anonymous HTTPS (public repos only). Every clone ends with an SSH `origin`, like your existing repos.
- **On a fresh Mac** the private repos usually can't be reached during the first run: 1Password was just installed and its SSH agent isn't on yet. Those are listed in the summary instead of failing the run. Turn the agent on, then run `./setup.sh --only repos`.
- **Privacy:** `repos.conf` is public, so the *names* of private repos listed there are visible; their contents aren't.

## Secrets and signed commits

**Secrets** never go in the repo. `configs/secrets/` mirrors `$HOME` with templates that hold 1Password *references* instead of values:

```bash
# configs/secrets/.zshrc.local
export ANTHROPIC_API_KEY="op://Personal/Anthropic API/credential"
```

`48-secrets.sh` fills in each template and writes the result to the same path under `$HOME` with mode 600. `~/.zshrc` sources `~/.zshrc.local` last.
- **Every template is a shell file unless it ends in `.yml`, `.yaml`, `.json` or `.toml`.** Shell templates may contain only comments, blank lines and `export NAME="op://…"`. Each value is fetched with `op read` and written single-quoted, so a value containing a quote, `$` or backtick can never run as code, whatever startup file it lands in (`.zlogin`, `config.fish`, …).
- **Data files** keep their text with each reference replaced by its value. Put references inside double quotes there: a value containing a quote, backslash or line break is refused, since it could change the file's structure.
- **Getting a reference:** in 1Password, open the item and use the field's menu → *Copy Secret Reference*.
- **What gets logged:** only changed or unchanged, never a value. An older rendered file is backed up before it's replaced.
- **When 1Password isn't ready:** if `op` isn't installed or the app's CLI integration is off, the run continues with a follow-up note instead of failing.
- **Approvals:** 1Password asks you to approve (Touch ID) the first time setup reads secrets.

**Signed commits:** `.gitconfig` signs every commit and tag with your 1Password "SSH Key" through `op-ssh-sign`.
- **Touch ID:** 1Password asks for it when signing; approve it for the terminal app once to stop the prompts.
- **Local verification:** `~/.config/git/allowed_signers` lets `git log --show-signature` verify your signatures.
- **One step on GitHub:** add the same public key as a **Signing key** (Settings → SSH and GPG keys → New SSH key → Key type: *Signing Key*). Until then GitHub shows your commits as *Unverified*. With the CLI instead:
  ```bash
  gh auth refresh -s admin:ssh_signing_key
  ssh-add -L | grep ' SSH Key$' > /tmp/signing.pub && gh ssh-key add /tmp/signing.pub --type signing --title "1Password SSH Key"
  ```

## Language runtimes

Your mise config (`configs/home/.config/mise/config.toml`) is linked like any dotfile, and `47-runtimes.sh` installs every tool in its `[tools]` table that has no version installed yet, with `mise install`.

- **Versions follow the config.** Yours asks for `latest` and `lts`, so a new Mac gets the newest releases on the day it's set up, not the exact versions on this Mac. To reproduce exact versions instead, pin them (`node = "24.22.1"`). On a Mac that already has a tool, nothing changes; move to newer releases with `mise upgrade`.
- **Missing is decided locally:** tools named in the config versus `mise ls --installed`. mise's own remote lookups silently drop tools whose "latest" can't be resolved (slow network, offline), which would hide real gaps.
- **Project tools aren't installed here.** `mise install` runs from `$HOME`, so only the global config counts. Repos with their own `mise.toml` install their tools when you first `cd` into them and trust the file.

## Apps installed outside Homebrew

If a cask in the Brewfile is already in `/Applications` because you downloaded it from the vendor, `brew bundle` would refuse to install over it. The packages step handles that per app:

- **Same version as the cask:** it adopts the app (`brew install --cask --adopt`), so Homebrew manages it from then on. Nothing is downloaded again.
- **Different version:** it leaves the app alone and skips that cask, with a warning that says how to hand it over (`brew install --cask --force <cask>` once the app is quit).

On a new Mac, where none of these apps exist yet, every cask simply installs.

## App Store apps

`mas` lines in the Brewfile are installed separately from the rest, one at a time, by `mas`. They need an App Store sign-in that a fresh Mac may not have yet, and inside `brew bundle` one missing sign-in would fail the whole packages step.

- **Already installed:** skipped.
- **Can't install** (not signed in, or the install doesn't finish within 5 minutes): a warning per app and one follow-up note. Sign in to the App Store app, then run `./setup.sh --only packages`.
- **Skipping some on purpose,** as CI does: `HOMEBREW_BUNDLE_MAS_SKIP="1432731683 …" ./setup.sh`.

## Moving Claude data between Macs

Chats on claude.ai and in the Claude app's Chat tab live in your Anthropic account and come back when you sign in. Claude Code sessions don't: their transcripts, memory, settings and the desktop app's session list are local files. `migrate/` moves those through iCloud Drive.

**On the old Mac:** quit the Claude app and any `claude` sessions, then from Terminal:
```bash
migrate/claude-backup.sh --dry-run   # what it will save, and repos with local-only work
migrate/claude-backup.sh             # asks for a password, writes the image
```
- **What's in the image:** `~/.claude`, `~/.claude.json`, and `~/Library/Application Support/Claude`. Caches, logs, runtime state and the bundled Claude Code binary are left out (they're regenerated), and so are Electron's lock files (restoring those stops the app launching). Typically under 100 MB.
- **Where it goes:** `claude-<run-id>.dmg` (AES-256, encrypted with your password) and a plain `claude-<run-id>.txt` summary, written to the `destination` in `configs/claude-backup.conf`. That's iCloud Drive by default. The image is encrypted because transcripts contain everything read or written in a session, and iCloud Drive is only end-to-end encrypted with Advanced Data Protection.
- **The password:** save it in 1Password. Without it the image can't be opened.
- **Repos at risk:** git repos under `scan` with uncommitted changes, unpushed commits, stashes or no remote are listed in the output and in the summary. Push them before wiping the old Mac.

**On the new Mac,** after Omamas has run and iCloud Drive has synced:
```bash
migrate/claude-restore.sh --dry-run  # preview
migrate/claude-restore.sh            # newest image, or pass one: claude-restore.sh path/to/claude-….dmg
```
- **Safety checks:** it refuses while Claude is running, and refuses a backup made for a different username or home folder. Sessions are filed by absolute path, so they wouldn't resume; pass `--force` to restore anyway.
- **What it changes:** each item is made to match the backup. What it replaces is copied to `~/.local/state/omamas/backups/<run-id>/claude-restore/` first. The new Mac's bundled Claude Code and caches are left alone.
- **Your login:** credentials live in the Keychain and are never backed up. Open Claude and sign in.
- **Getting sessions back:** clone your repos to the same paths they had (e.g. `~/Work/github.com/...`) for `claude --resume` and the Code tab to find their sessions.

Anthropic doesn't document a migration path, so treat the desktop app's session list as best effort; `~/.claude` is plain files and restores reliably.

## Dock, default apps, login items, security

| Module | What it does | Notes |
|---|---|---|
| `62-dock` | The Dock holds exactly the apps in `dock.conf`, in order, and no folders or stacks. | Yours is empty, so a new Mac's default apps and Downloads stack are removed. Delete `dock.conf` to leave the Dock alone. Rebuilds and restarts the Dock only when it differs. |
| `64-default-apps` | Sets handlers with `duti` (Brave for web links and HTML, Obsidian for Markdown). | Reads each one first. macOS asks you to confirm a new default browser; until you do, it's a follow-up, not a success. |
| `66-login-items` | Adds the apps in `login-items.conf` to Login Items through System Events. | Never removes any. If access to System Events is declined or the prompt isn't answered within 20 seconds, it leaves a follow-up instead of waiting. |
| `17-security` | Sets the application firewall and stealth mode; reports FileVault. | With the firewall on, macOS asks once whether an unsigned program (a dev server, say) may accept incoming connections. FileVault is never turned on automatically: that needs you and produces a recovery key. |

## Weekly drift check

Machines drift: you install an app without adding it to the Brewfile, flip a setting in System Settings, rearrange the Dock, or an app rewrites a linked config. `70-drift-check.sh` installs a LaunchAgent (`~/Library/LaunchAgents/com.omamas.drift-check.plist`) that runs `scripts/drift-check.sh` on the schedule in `configs/drift-check.conf` (Mondays at 10:00).

The check runs `./setup.sh --dry-run`, so it never changes anything, and reports:
- modules with pending changes (something on the Mac no longer matches `configs/`)
- apps installed with Homebrew but missing from the Brewfile
- modules that failed
- uncommitted or unpushed changes in the Omamas repo (an app editing a linked dotfile shows up here)

**When it notifies you:** only if something differs. The notification comes from Script Editor, so allow notifications for it the first time. Every run writes `~/.local/state/omamas/drift/latest.txt`.
**What's left out:** login items, because their check needs a permission prompt a background job can't answer (`skip` in the config).
**On demand:** `scripts/drift-check.sh`, or `--no-notify` to just print it.
**Turning it off:** delete `configs/drift-check.conf`; the next `./setup.sh` removes the agent.

**Fixing drift:** either update `configs/` to match what you changed (e.g. add the app to the Brewfile, or re-capture with `./capture.sh`), or run `./setup.sh` to put the Mac back the way the configs say.

## Computer name

`02-computer-name.sh` names the Mac from `configs/macos/computer-name.conf` (`Bizarro`). It sets the friendly ComputerName (Finder, AirDrop), and derives the network names LocalHostName (`Bizarro.local`) and HostName (what `hostname` prints) from it, replacing characters they don't allow with hyphens. It only asks for sudo when a name actually changes.

While the old and new Mac are both on the same network with the same name, macOS adds a number to one's network name (`Bizarro-2.local`). Once the old Mac is wiped or renamed, run `./setup.sh --only computer-name` on the new one to settle it.

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
   - CI does this on every push: `.github/workflows/ci.yml` bootstraps through `install.sh` on an ephemeral `macos-latest` runner and fails if the second run changes anything. CI can't answer prompts, run as your user, or start from a truly bare Mac, so also rehearse in a VM (next section).

## Rehearsing in a VM

[UTM](https://mac.getutm.app) (in the Brewfile) runs macOS virtual machines with Apple's own virtualization. `tests/rehearse.sh` wraps its `utmctl` command, so each rehearsal starts from a factory-fresh Mac and leaves nothing behind.

**Once: build the base VM** (about 30 minutes, mostly downloading macOS):
1. In UTM: **+** → **Virtualize** → **macOS 12+**. Leave the installer (IPSW) field empty to download the latest macOS from Apple. Give it **8 GB** of memory, **4** CPU cores and **80 GB** of disk, and name it exactly **`omamas-base`**. Save, then press play and let macOS install.
2. When the installer finishes, shut the VM down. Then run:
   ```bash
   tests/rehearse.sh provision
   ```
   This asks for a password and boots the VM once, creating your user (`el-kal`, same as this Mac, so paths and Claude sessions line up), logging in automatically and turning on SSH. It skips Setup Assistant (needs macOS 27 on host and guest). At the desktop, shut down from the Apple menu: that's your clean base.

**Every rehearsal:**
```bash
tests/rehearse.sh start   # a disposable copy: nothing it does is saved
```
- **In the VM:** open Terminal and run the printed one-liner. Click through the prompts the checklist describes.
- **Afterwards:** run `./setup.sh` again and expect `0 changed`.
- **When you're done:** `tests/rehearse.sh stop` throws the whole run away.

**What's different from a real Mac:**
- **No Touch ID:** sudo asks for the password, which tests that fallback.
- **App Store:** signing in inside a VM is unreliable, so the `mas` apps usually end up as a follow-up note there. That's expected; skip them with `HOMEBREW_BUNDLE_MAS_SKIP="<ids>" ./setup.sh`.
- **Prompts:** the first `utmctl` command asks to let your terminal control UTM; allow it.

To test `install.sh` against a local branch without pushing:
```bash
cat install.sh | OMAMAS_REPO="file://$PWD" OMAMAS_REF=$(git branch --show-current) OMAMAS_DIR=/tmp/omamas-try bash -s -- --dry-run
```

## Security

- **What runs on a new Mac is protected.** The one-liner installs `main` and runs it with `sudo`, so a ruleset on `main` blocks force-pushes and deletion and requires **signed commits**. Yours are signed with your 1Password key.
- **No secrets in the repo.** Secret values never enter git: `configs/secrets/` holds 1Password references, and Claude backups are encrypted images outside the repo. GitHub secret scanning and push protection are on.
- **CI can't write.** The workflow pins its token to read-only, even though the e2e job runs third-party installers, and checkout leaves no git credentials on disk. Actions are pinned to commit hashes, and Dependabot proposes updates.
- **sudo only as long as it's needed.** `setup.sh` asks once, up front, and keeps the ticket fresh only until `20-packages`, the last module that needs it. Then it drops the ticket (`sudo -k`), so repo clones, runtime downloads, secrets and everything after can't use `sudo` without asking.
- **No check-then-swap gaps.** What root installs (the Touch ID PAM file, the Homebrew installer) stays in memory between being checked and being used, never in a temp file another process could replace. The `/tmp` marker for the Command Line Tools is created with `O_EXCL|O_NOFOLLOW`, which refuses a planted symlink.
- **Config values can't become code.** Values reach AppleScript as arguments, never as script text; `repos.conf` lines must be exactly `host/owner/repo`; `directories.conf` paths must stay under `~`, with octal modes and no symlink anywhere along the way; `defaults.conf` takes preference domains, never file paths; secrets in shell files are single-quoted.
- **Some config *is* code.** The Brewfile is Ruby, `configs/home/` dotfiles are shell, and `.config/mise/config.toml` can carry `[hooks]` that run on `mise install` and in every shell. Review changes to those like changes to a script.
- **SSH host keys are pinned.** GitHub's published host keys are linked to `~/.ssh/github_known_hosts`, and `~/.ssh/config` trusts them for github.com, so neither `45-repos` nor everyday `git`/`ssh` accepts whatever answers first on a fresh Mac. Other hosts must already be in `~/.ssh/known_hosts`.
- **Logs and backups are private.** `~/.local/state/omamas` is kept at mode 700, and a repo URL is logged without any username or token in it.
- **Backups need a long password.** New Claude backups require 12+ characters, because the image sits in iCloud, where a short password can be guessed offline. `OMAMAS_BACKUP_PASSWORD` is read and removed from the environment as soon as the script starts.
- **Test hooks are off in real runs.** Overrides that choose which program runs, or what root writes to (`OMAMAS_SOCKETFILTERFW`, `OMAMAS_PAM_DIR`, …), only apply with `OMAMAS_TEST_MODE=1`, which the test suite sets.

## Environment variables

| Variable | Effect |
|---|---|
| `OMAMAS_DIR` / `OMAMAS_REPO` / `OMAMAS_REF` | Where `install.sh` clones the repo, from which URL, and which branch |
| `OMAMAS_CONFIG_DIR` | Use a different State tier (handy for sandboxes and per-machine profiles) |
| `OMAMAS_UPGRADE=1` | Also `brew update` and upgrade outdated packages (same as `--upgrade`) |
| `OMAMAS_CAPTURE_DOMAINS` | Preference domains `capture.sh` inspects (default: a curated list of macOS domains) |
| `OMAMAS_BACKUP_PASSWORD` | Password for `migrate/` images without a prompt (automation and tests; prefer the prompt) |
| `OMAMAS_PAM_DIR` | Use a different PAM directory than `/etc/pam.d` (used by the tests) |
| `OMAMAS_NO_RESTART=1` | Don't quit or restart Dock, Finder or System Settings; add a follow-up note instead |
| `OMAMAS_MIN_MACOS` | Minimum macOS version allowed by pre-flight (default `14.0`) |
| `OMAMAS_DRY_RUN=1` | Same as `--dry-run` |
| `NO_COLOR` | Plain output |
| `OMAMAS_TEST_MODE=1` | Lets the test suite point modules at fake tools; ignored otherwise |
