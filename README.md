<p align="center">
  <img src="assets/logo.png" alt="Omamas logo: a terminal prompt and cursor inside a blue-to-violet ring" width="160">
</p>

# Omamas

*お任せ + macOS.* You leave the machine to it: one command turns a factory-reset Mac into your development environment. Running it again on a Mac you already use reconciles that machine back to the declared state, changing only what has drifted.

Omamas is "workstation as code" for macOS, written in plain Bash that runs on the `/bin/bash` 3.2 every Mac ships with. What you want lives in `configs/` as data: a Brewfile, dotfiles, macOS preferences, repos, runtimes. Small, standalone modules in `scripts/` make the Mac match it.

- **One command** from a fresh Mac: Command Line Tools, Rosetta 2, Homebrew, apps, dotfiles, settings, repos, language runtimes.
- **Idempotent and non-destructive.** Every item is checked before it's touched, and anything replaced is backed up first. A second run changes nothing; CI enforces it.
- **Dry run everywhere.** `--dry-run` shows exactly what would change.
- **Capture** drafts `configs/` from a Mac you already use, so you start from your real setup.
- **Weekly drift check** tells you when the Mac and the repo disagree.
- **Secrets from 1Password**, never in git. Commits signed with a 1Password SSH key.
- **Claude Code sessions** move between Macs in an encrypted backup.
- **Tested** in a sandbox, end to end on a fresh macOS runner in CI, and in disposable UTM virtual machines.

> [!NOTE]
> The `configs/` in this repo are its author's. Running the one-liner as-is installs *their* apps and settings and names your Mac after theirs. To use Omamas, [make it yours](#make-it-yours) first.

## Contents

- [Make it yours](#make-it-yours)
- [What a first run looks like](#what-a-first-run-looks-like)
- [What's included](#whats-included)
- [How it works](#how-it-works)
- [Configuration](#configuration)
- [Keeping a Mac and the repo in sync](#keeping-a-mac-and-the-repo-in-sync)
- [Modules in detail](#modules-in-detail)
- [Security](#security)
- [Development](#development)
- [Environment variables](#environment-variables)
- [License](#license)

## Make it yours

**Requirements:** macOS 14 (Sonoma) or newer (Apple silicon or Intel; developed and tested on Apple silicon), an admin account, and a GitHub account for your fork. Nothing else needs to be installed first.

1. **Fork this repo**, and clone your fork on the Mac whose setup you want to reproduce.
2. **Point the bootstrap at your fork:** change `OMAMAS_REPO` (and the URLs in the comments) in `install.sh`.
3. **Capture your Mac:**
   ```bash
   ./capture.sh
   ```
   It writes drafts to `drafts/` and changes nothing. Use them to replace the files in `configs/` (see [Capturing an existing Mac](#capturing-an-existing-mac)).
4. **Replace the remaining personal values:**

   | File | What to change |
   |---|---|
   | `configs/macos/computer-name.conf` | your Mac's name |
   | `configs/repos.conf` | your repos (or delete the file) |
   | `configs/home/.gitconfig`, `configs/home/.config/git/allowed_signers` | your name, email and signing key, or drop signing |
   | `configs/macos/default-apps.conf`, `dock.conf`, `login-items.conf` | your apps |
   | `configs/macos/defaults.conf` | your preferences; one Finder path contains the author's username |
   | `configs/claude-backup.conf` | where Claude backups go (or delete it if you don't use `migrate/`) |
   | `tests/rehearse.sh` | the repo path in the one-liner it prints |

   Any manifest you delete turns its module off.
5. **Check it on your Mac:** `./setup.sh --dry-run` should report almost nothing pending, since you captured from this machine. Then run `tests/run.sh`.
6. **Rehearse on a fresh Mac** in a [UTM virtual machine](#rehearsing-in-a-vm), then commit and push.
7. **On a new Mac:**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/<you>/omamas/main/install.sh | OMAMAS_DIR=~/path/to/omamas bash
   ```
   Dotfile symlinks point into the checkout, so choose a permanent `OMAMAS_DIR` (default `~/.local/share/omamas`). If `repos.conf` lists your fork too, use the same path it would clone to, so you don't end up with two copies. Pass flags with `bash -s --`, e.g. `| bash -s -- --dry-run`.

## What a first run looks like

**Before you start:** sign in to the App Store if your Brewfile has `mas` apps, enroll a Touch ID fingerprint, plug a laptop in, and make sure you're online.

**The first few minutes need you:**
- Your password, once. Omamas then switches sudo to Touch ID.
- A Command Line Tools dialog, only if the silent install isn't available.
- "Terminal wants to control **System Settings**" and "**System Events**": allow both, for preferences and login items.
- macOS asking to confirm a new default browser, if you set one.
- Signing in to 1Password, which is installed and opened early. The run doesn't wait for it.
- Some cask installers asking for a password or permission.

**After that it's unattended.** The summary lists failed modules, follow-ups (things only you can do, each with the command to re-run), the log file and the backup folder. Re-running is always safe.

**Afterwards:** open a new terminal, log out and back in if the summary asks, turn on 1Password's SSH agent and CLI integration, re-run any module a follow-up names, sign in to your apps, and confirm with `./setup.sh --dry-run`, which should show nothing pending.

## What's included

Modules run in numeric order. Each one also runs on its own, e.g. `scripts/40-dotfiles.sh --dry-run`.

| Module | Does |
|---|---|
| `02-computer-name` | Sets the computer, Bonjour and host names |
| `05-sudo-touchid` | Enables Touch ID for `sudo` in a way that survives macOS updates |
| `07-rosetta` | Installs Rosetta 2 on Apple silicon |
| `10-homebrew` | Installs Homebrew |
| `15-1password` | Installs 1Password early, so you can sign in while the rest installs |
| `17-security` | Turns on the firewall and stealth mode; reports FileVault |
| `20-packages` | Installs the Brewfile (formulae, casks, App Store apps) and reports drift |
| `30-directories` | Creates directories with the right permissions |
| `40-dotfiles` | Symlinks `configs/home/` into `~`, backing up what it replaces |
| `45-repos` | Clones your repos to `~/Work/<host>/<owner>/<repo>` |
| `47-runtimes` | Installs language runtimes with mise |
| `48-secrets` | Renders 1Password references into files like `~/.zshrc.local` |
| `50-fonts` | Installs font files |
| `60-macos-defaults` | Applies `defaults` preferences, restarting Dock or Finder only when needed |
| `62-dock` | Sets the Dock's apps, in order |
| `64-default-apps` | Sets which app opens links and file types |
| `66-login-items` | Adds apps to Login Items |
| `70-drift-check` | Installs the weekly drift check |

**The config in this repo,** as an example of a real setup:
- about 60 command-line tools and 40 casks (apps and fonts) from Homebrew, plus 3 App Store apps
- 157 macOS preferences, mostly trackpad, mouse, Dock, Finder and screenshots
- zsh split into fragments, with starship, zoxide, fzf, autosuggestions and syntax highlighting
- Node, Python, Go, Ruby, Bun and Zig through mise
- git commits signed with 1Password, and SSH through 1Password's agent

## How it works

### Layout

```
omamas/
├── install.sh                 Orchestration · remote bootstrap (curl | bash)
├── setup.sh                   Orchestration · local runner: pre-flight, log, sudo, modules
├── capture.sh                 Read-only: drafts configs/ from the current Mac into drafts/
├── migrate/                   Claude data between Macs (not part of setup.sh)
├── configs/                   State · what should exist. No logic.
│   ├── Brewfile                 formulae, casks, taps, mas apps
│   ├── home/                    mirror of $HOME; every file is symlinked into place
│   ├── secrets/                 templates with op:// references, rendered into $HOME
│   ├── macos/                   name, preferences, Dock, default apps, login items, security
│   └── *.conf                   directories, repos, drift check, Claude backup
├── scripts/                   Imperative · how to get there
│   ├── utils.sh, symlink.sh     shared libraries (sourced)
│   ├── _template.sh             copy to start a new module
│   ├── NN-*.sh                  the modules
│   └── drift-check.sh           the weekly report (run by a LaunchAgent)
├── tests/                     Sandboxed tests, plus rehearse.sh for UTM
└── .github/                   CI and Dependabot
```

**Tier rules**
- `configs/` holds data only. If you're tempted to write an `if` there, put it in a module. (`Brewfile` is technically Ruby; keep it to one declaration per line.)
- `scripts/` holds logic and never hardcodes what gets installed. Each module reads its own manifest.
- The root scripts only sequence work. `setup.sh` runs each module as a separate process (`"$BASH" scripts/NN-x.sh`), so a module behaves the same whether `setup.sh` runs it or you do.

### A run

`install.sh`
1. Checks it's on macOS and not running as root.
2. Installs the Xcode Command Line Tools: headless through `softwareupdate`, falling back to Apple's installer.
3. Clones the repo to `OMAMAS_DIR`, or fast-forwards an existing clone that has no local changes.
4. Hands off to `setup.sh`, reattaching the terminal so prompts work under `curl | bash`.

The whole script sits inside `main`, called on the last line, so a truncated download can't run a partial script.

`setup.sh`
1. Takes a lock, so two runs can't overlap.
2. Mirrors all output to `~/.local/state/omamas/logs/setup-<run-id>.log`; `latest.log` points at the newest.
3. Pre-flight: macOS version, not root, configs present, network, disk space.
4. Asks for sudo once, only if a selected module carries `# omamas: requires-sudo`, keeps it fresh until the last such module finishes, then drops it. `caffeinate` keeps the Mac awake.
5. Runs each module and records ok / FAILED and how long it took. A failure doesn't stop the run unless you pass `--fail-fast`.
6. Prints a summary, follow-ups, and the log and backup paths. Exits non-zero if any module failed.

```
./setup.sh [-n|--dry-run] [-o|--only NAME]... [-s|--skip NAME]... [-l|--list] [--fail-fast] [--upgrade]
```

### Guarantees

| Principle | Mechanism |
|---|---|
| **Idempotency** | Every item is checked first: already right (`[SKIP]`) or changed (`[SUCCESS]`). Each module ends with `name: N changed, M unchanged`; CI fails if a second run changes anything. |
| **Non-destructive** | Before a file is replaced, it's moved to `~/.local/state/omamas/backups/<run-id>/<path relative to ~>`, and a backup is never overwritten. Nothing of yours is deleted: the only removals are symlinks Omamas created, its own temp files, and a clone that failed halfway. |
| **Declarative removal** | `40-dotfiles` records the links it owns; a link whose source left `configs/home/` is removed if it still points there. Packages are never uninstalled, only reported as drift. |
| **Dry run** | `--dry-run` (or `-n` on any module) routes every change through `run` / `log_dry` and changes nothing. |
| **Fail-safe** | `set -Eeuo pipefail`; the ERR trap names the failing command, file and line; EXIT hooks clean up; Ctrl-C exits 130. |
| **Telemetry** | `[INFO] [SKIP] [SUCCESS] [WARN] [ERROR] [DRY]`, timestamped, colored only on a terminal without `NO_COLOR`. |

To restore from a backup, copy it back over your home directory:
```bash
cp -a ~/.local/state/omamas/backups/<run-id>/. ~/
```

## Configuration

| File | Format | Module |
|---|---|---|
| `configs/macos/computer-name.conf` | the name | `02-computer-name` |
| `configs/macos/security.conf` | `firewall on\|off`, `stealth on\|off`, `filevault check` | `17-security` |
| `configs/Brewfile` | `brew "x"`, `cask "y"`, `tap "a/b"`, `mas "App", id: N` | `20-packages` |
| `configs/directories.conf` | `<path> [octal-mode]` | `30-directories` |
| `configs/home/**` | file at `configs/home/P` → symlink at `~/P` | `40-dotfiles` |
| `configs/repos.conf` | `<host>/<owner>/<repo>` | `45-repos` |
| `configs/home/.config/mise/config.toml` | mise `[tools]`, e.g. `node = "lts"` | `47-runtimes` |
| `configs/secrets/**` | templates with `op://` references | `48-secrets` |
| `configs/fonts/*` | font files | `50-fonts` |
| `configs/macos/defaults.conf` | `<domain> <key> <-bool\|-int\|-float\|-string> <value…>` | `60-macos-defaults` |
| `configs/macos/dock.conf` | one app path per line, in order | `62-dock` |
| `configs/macos/default-apps.conf` | `<bundle-id> <url-scheme>` or `<bundle-id> <type-id> <role>` | `64-default-apps` |
| `configs/macos/login-items.conf` | `<app path> [hidden]` | `66-login-items` |
| `configs/drift-check.conf` | `weekday`, `hour`, `minute`, `skip <module>` | `70-drift-check` |
| `configs/claude-backup.conf` | `destination <dir>`, `scan <dir>` | `migrate/` |

In `.conf` files, `#` lines and blank lines are ignored and a leading `~` expands to `$HOME`. A missing manifest turns its module off.

**Dotfiles** are linked file by file, never as whole directories, so apps can keep their own state beside your managed files without it entering the repo. Because the links point into the checkout, keep it in one place. Editors write through a link; a tool that replaces the file instead (`sed -i`, some apps) breaks it, and the next run backs the plain file up and restores the link.

**zsh** is split into numbered fragments in `~/.config/zsh/`, sourced in name order by `~/.zshrc`, then `~/.zshrc.local` (rendered secrets, never committed):

| Fragment | Holds |
|---|---|
| `10-path.zsh` | PATH additions |
| `20-history.zsh` | history, kept in `~/.local/state/zsh` |
| `30-completion.zsh` | `compinit`, once |
| `40-aliases.zsh` | aliases |
| `50-tools.zsh` | tool setup (`mise`, `zoxide`, `fzf`, `starship`, …), each guarded by `command -v` so a missing tool never breaks the shell |
| `90-plugins.zsh` | Homebrew-installed plugins; syntax highlighting loads last |

Add a feature with a new numbered file. If an installer appends to `~/.zshrc`, it has edited the repo file through the link: move those lines into a fragment.

## Keeping a Mac and the repo in sync

A new Mac gets what's committed and pushed. Edits to linked dotfiles, and `mise use -g`, land in the repo by themselves, since you're editing the repo's files. Everything else (packages, preferences, the Dock, new config files, repos) reaches the repo when you add it to `configs/`. Two tools help.

### Capturing an existing Mac

`./capture.sh` drafts `configs/` from the Mac you're on: the first time, and after you've changed a lot without updating the repo. It's read-only and writes only to `drafts/<run-id>/` (git-ignored):

| Draft | Source | What it gives you |
|---|---|---|
| `Brewfile` | `brew bundle dump` | everything installed on request, with descriptions |
| `dotfiles.md` | scan of `~` and `~/.config` | adoption candidates, files that look like they hold secrets, config and app-data directories, and `cp` commands for the clean ones |
| `macos/defaults.conf` | `defaults export` on common domains | explicitly set preferences with their real types; `$HOME` paths rewritten as `~` |

macOS keeps no record of factory defaults, so the preferences draft lists keys that are *set*, not *changed*: keep the ones that express a choice. The secret scan reports only the kind of match, never the value.

```bash
./capture.sh                                   # or: --only brew|dotfiles|defaults
diff -u configs/Brewfile drafts/*/Brewfile     # prune, then copy over
OMAMAS_CAPTURE_DOMAINS="com.apple.dock com.googlecode.iterm2" ./capture.sh --only defaults
./setup.sh --dry-run                           # after adopting: ~0 pending on this Mac
```

### Weekly drift check

`70-drift-check` installs a LaunchAgent that runs `scripts/drift-check.sh` on the schedule in `configs/drift-check.conf`. It runs `./setup.sh --dry-run`, so it changes nothing, and reports modules with pending changes, Homebrew packages missing from the Brewfile, failed modules, and uncommitted or unpushed changes in the repo.

- **Notification:** only when something differs (from Script Editor; allow it the first time). Every run writes `~/.local/state/omamas/drift/latest.txt`.
- **Left out:** login items, whose check needs a permission prompt a background job can't answer (`skip` in the config).
- **On demand:** `scripts/drift-check.sh`, or `--no-notify` to just print.
- **Fixing drift:** update `configs/` to match, or run `./setup.sh` to put the Mac back.
- **Turning it off:** delete `configs/drift-check.conf`; the next run removes the agent.

## Modules in detail

### Packages

- **Apps installed outside Homebrew:** if a cask's app is already in `/Applications`, the same version is adopted (`brew install --cask --adopt`); a different version is left alone with a warning explaining how to hand it over.
- **App Store apps** install separately, one at a time with `mas`, so a missing App Store sign-in doesn't fail everything else. An app that can't install becomes a follow-up. Skip some on purpose with `HOMEBREW_BUNDLE_MAS_SKIP="<ids>"`, as CI does.
- **Drift:** packages installed but not in the Brewfile are reported, never uninstalled.

### Repos

`45-repos` clones each repo in `repos.conf` that isn't checked out yet, to `~/Work/<host>/<owner>/<repo>`. Existing checkouts are never fetched, pulled or changed.
- **Access:** SSH first (1Password's agent), then HTTPS with `gh auth login`, then anonymous HTTPS. Every clone ends with an SSH `origin`.
- **Fresh Mac:** private repos usually can't be reached on the first run, before 1Password's SSH agent is on. They're listed as a follow-up: turn the agent on, then `./setup.sh --only repos`.
- **Privacy:** if your repo is public, the *names* of private repos in `repos.conf` are visible.

### Secrets

`configs/secrets/` mirrors `$HOME` with templates holding 1Password references, never values:
```bash
# configs/secrets/.zshrc.local
export ANTHROPIC_API_KEY="op://Personal/Anthropic API/credential"
```
`48-secrets` writes each one to the same path under `~` with mode 600.
- **Shell files:** every template is one unless it ends in `.yml`, `.yaml`, `.json` or `.toml`. Only comments and `export NAME="op://…"` lines are allowed, and each value is fetched with `op read` and written single-quoted, so no value can run as code.
- **Data files** keep their text with references replaced; a value with a quote, backslash or line break is refused. Put references in double quotes there.
- **References:** in 1Password, the field's menu → *Copy Secret Reference*.
- **Not ready:** without `op` or the app's CLI integration, the run continues with a follow-up. Only "changed" or "unchanged" is ever logged.

### Signed commits

The shipped `.gitconfig` signs every commit and tag with a 1Password SSH key through `op-ssh-sign`, and `~/.config/git/allowed_signers` lets `git log --show-signature` verify them. Register the same public key on GitHub as a **Signing key** to have commits show as *Verified*. Replace both files with your own, or remove signing.

### Runtimes

`47-runtimes` installs every tool in mise's global `[tools]` table that has no version installed, with `mise install`. `latest` and `lts` resolve on the day a Mac is set up; pin versions (`node = "24.22.1"`) to reproduce exact ones. Existing tools are never upgraded; use `mise upgrade`. Repos with their own `mise.toml` install their tools when you `cd` into them.

### Dock, default apps, login items, security

| Module | What it does | Notes |
|---|---|---|
| `62-dock` | The Dock holds exactly the apps in `dock.conf`, in order, with no folders or stacks. | An empty `dock.conf` clears it; delete the file to leave the Dock alone. Restarts the Dock only when it differs. |
| `64-default-apps` | Sets handlers with `duti`. | macOS asks you to confirm a new default browser; until you do, it's a follow-up. |
| `66-login-items` | Adds apps to Login Items through System Events. | Never removes any. If access isn't granted within 20 seconds, it leaves a follow-up. |
| `17-security` | Firewall and stealth mode; reports FileVault. | FileVault is never turned on automatically: that needs you and produces a recovery key. |

### Computer name

`02-computer-name` sets ComputerName from `computer-name.conf` and derives LocalHostName and HostName from it, replacing characters they don't allow with hyphens. While two Macs with the same name share a network, macOS numbers one (`Name-2.local`); once the old one is gone, `./setup.sh --only computer-name` settles it.

### Touch ID for sudo

`05-sudo-touchid` creates `/etc/pam.d/sudo_local` from Apple's template with `pam_tid.so` enabled (macOS 14+), which survives OS updates, unlike edits to `/etc/pam.d/sudo`.
- **Fallback:** the password still works when Touch ID can't (no finger enrolled, lid closed, SSH).
- **Safety:** it only adds that line, keeps any others, backs up the old file, checks the result differs by exactly that line, and renames it into place.
- **tmux / screen:** add `brew "pam-reattach"` and put `auth optional /opt/homebrew/lib/pam/pam_reattach.so ignore_ssh` at the top of `sudo_local`.
- **Opt out / undo:** `--skip sudo-touchid`; `sudo rm /etc/pam.d/sudo_local`.

### Moving Claude data between Macs

Chats on claude.ai live in your Anthropic account. Claude Code sessions don't: transcripts, memory, settings and the desktop app's session list are local files. `migrate/` moves them through iCloud Drive.

```bash
# Old Mac, with Claude quit:
migrate/claude-backup.sh --dry-run   # what it saves, and repos with local-only work
migrate/claude-backup.sh             # asks for a password (12+ characters), writes the image
# New Mac, after Omamas has run and iCloud Drive has synced:
migrate/claude-restore.sh --dry-run
migrate/claude-restore.sh
```
- **What's saved:** `~/.claude`, `~/.claude.json` and `~/Library/Application Support/Claude`, minus caches, logs and lock files. An AES-256 image plus a plain summary go to the `destination` in `claude-backup.conf`. It's encrypted because transcripts contain everything a session read or wrote.
- **Repos at risk:** repos under `scan` with uncommitted, unpushed or stashed work are listed. Push them before wiping the old Mac.
- **Restore:** it refuses while Claude runs, or for a backup from a different username (sessions are filed by path; `--force` overrides). Whatever it replaces is backed up first. Credentials stay in the Keychain: sign in again.
- **Resuming sessions** needs your repos at their old paths, which `45-repos` provides.

Anthropic doesn't document a migration path, so treat the desktop app's session list as best effort; `~/.claude` restores reliably.

## Security

- **`main` is what a new Mac runs**, with your admin rights. Protect it: block force-pushes and deletion, and require signed commits. Turn on secret scanning and push protection.
- **No secret values in git.** `configs/secrets/` holds 1Password references; Claude backups are encrypted images outside the repo.
- **Least privilege.** sudo is held only until `20-packages`, the last module that needs it, then dropped. CI's token is read-only, checkout keeps no credentials, and actions are pinned to commit hashes, updated by Dependabot.
- **Config values are data.** They reach AppleScript as arguments and shell files single-quoted; repo names, directory paths and modes, and preference domains are validated; a directory is never changed through a symlink. What root writes is checked and written from memory, never from a temp file another process could swap.
- **No trust on first use.** GitHub's SSH host keys are pinned (`configs/home/.ssh/github_known_hosts`) for repo clones and everyday `git`.
- **Private by default.** Logs and backups live in a mode-700 folder; URLs are logged without credentials. Test-only overrides work only under `OMAMAS_TEST_MODE=1`.

**Accepted trade-offs**, inherent to this kind of tool:
- `curl | bash` trusts whatever `main` holds: branch protection is the safeguard, not a signature check in `install.sh`.
- The Homebrew installer comes from its `HEAD`, as Homebrew documents.
- Some config *is* code and runs during the sudo window or at shell start: the Brewfile (Ruby), dotfiles (shell), and mise's config (`[hooks]`). Review changes to them like changes to a script.

## Development

### Adding a module

```bash
cp scripts/_template.sh scripts/55-example.sh   # the number decides the order
$EDITOR scripts/55-example.sh configs/example.conf
scripts/55-example.sh --dry-run
```

The contract, spelled out in `_template.sh`:
1. **Standalone:** source `utils.sh` and check your own prerequisites instead of assuming earlier modules ran.
2. **Check, then act:** each item is either `log_skip` or changed and `log_success`.
3. **Data comes from `configs/`,** read with `read_manifest`.
4. **Mutations go through `run`,** or an explicit `is_dry_run` branch.
5. **Per-item failures** go to `log_error` and the loop continues; `module_finish` turns them into a non-zero exit.
6. **Needs admin rights?** Add `# omamas: requires-sudo` and number it before `20-packages`: sudo is dropped after the last such module, and a test enforces it.

Only `NN-*.sh` files are modules.

**Bash 3.2.** A fresh Mac only has `/bin/bash` 3.2, so every script must run on it:
- no associative arrays, `mapfile`, or `${x,,}`
- expand possibly empty arrays as `${a[@]+"${a[@]}"}`
- count with `n=$((n+1))`, not `((n++))`, which returns 1 when `n` is 0 and kills the script under `set -e`
- inside a function called from `if` or `||`, `set -e` is off, so check every step explicitly
- never write `x=$(cond && echo y)`, which fails under `set -e` when `cond` is false

### Testing, from least to most invasive

1. **Sandboxed tests** against a fake `$HOME` and fixture configs (the `defaults` tests write to plist files, never your real preferences). Also runs `bash -n` and ShellCheck:
   ```bash
   tests/run.sh
   ```
2. **One module in a throwaway home:**
   ```bash
   export SANDBOX=$(mktemp -d); mkdir -p "$SANDBOX/home" "$SANDBOX/configs/home"
   echo 'echo hi' > "$SANDBOX/configs/home/.zshrc"
   HOME="$SANDBOX/home" OMAMAS_CONFIG_DIR="$SANDBOX/configs" scripts/40-dotfiles.sh   # twice: expect "0 changed"
   ```
3. **Dry run on your real Mac:** `./setup.sh --dry-run`, or with `--only <module>`.
4. **Real run, one module at a time:** `./setup.sh --only directories`, and so on; the same command again must report `0 changed`.
5. **End to end:** CI bootstraps through `install.sh` on a fresh `macos-latest` runner on every push and weekly, and fails if a second run changes anything. It can't answer prompts or start from a truly bare Mac, so also rehearse in a VM.

### Rehearsing in a VM

[UTM](https://mac.getutm.app) runs macOS virtual machines with Apple's virtualization; `tests/rehearse.sh` wraps its `utmctl`, so every rehearsal starts from a factory-fresh Mac and leaves nothing behind.

**Once, build the base VM** (about 30 minutes):
1. In UTM: **+** → **Virtualize** → **macOS 12+**. Leave the IPSW field empty to download the latest macOS, give it 8 GB of memory, 4 cores and 80 GB of disk, and name it **`omamas-base`**. Let macOS install, then shut it down.
2. `tests/rehearse.sh provision` creates your user (the same username as the host, so paths line up), turns on auto-login and SSH, and skips Setup Assistant (needs macOS 27 on host and guest). Shut down from the Apple menu: that's your clean base.

**Every rehearsal:** `tests/rehearse.sh start` boots a disposable copy and prints the one-liner to run inside it; `tests/rehearse.sh stop` throws it away. The VM has no Touch ID (which tests the password fallback), and App Store sign-in there is unreliable, so `mas` apps usually end up as a follow-up.

To test `install.sh` against a local branch without pushing:
```bash
cat install.sh | OMAMAS_REPO="file://$PWD" OMAMAS_REF=$(git branch --show-current) OMAMAS_DIR=/tmp/omamas-try bash -s -- --dry-run
```

## Environment variables

| Variable | Effect |
|---|---|
| `OMAMAS_DIR` / `OMAMAS_REPO` / `OMAMAS_REF` | Where `install.sh` clones the repo, from which URL, and which branch |
| `OMAMAS_CONFIG_DIR` | Use a different `configs/` (sandboxes, per-machine profiles) |
| `OMAMAS_UPGRADE=1` | Also `brew update` and upgrade outdated packages (same as `--upgrade`) |
| `OMAMAS_DRY_RUN=1` | Same as `--dry-run` |
| `OMAMAS_NO_RESTART=1` | Don't quit or restart Dock, Finder or System Settings; leave a follow-up instead |
| `OMAMAS_MIN_MACOS` | Minimum macOS version allowed by pre-flight (default `14.0`) |
| `OMAMAS_SKIP_NETWORK_CHECK=1` | Skip pre-flight's network check |
| `OMAMAS_PROMPT_TIMEOUT` | Seconds to wait on a permission or approval prompt before leaving a follow-up (per-module defaults, 20 to 300) |
| `OMAMAS_STATE_DIR` | Where logs, backups and link state live (default `~/.local/state/omamas`) |
| `OMAMAS_CAPTURE_DOMAINS` | Preference domains `capture.sh` inspects |
| `OMAMAS_BACKUP_PASSWORD` | Password for `migrate/` images without a prompt (automation and tests); removed from the environment once read |
| `NO_COLOR` / `OMAMAS_COLOR=0\|1` | Plain output, or force color on or off |
| `OMAMAS_TEST_MODE=1` | Lets the test suite point modules at fake tools; ignored otherwise |

## License

[MIT](LICENSE). The configs in this repo are one person's setup, shared as an example: replace them with your own.
