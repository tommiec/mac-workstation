# mac-workstation

Personal macOS setup for Homebrew tooling, weekly maintenance, diagnostics,
local AI and encrypted recovery backups.

> The `Brewfile` reflects my workstation. Fork the repository and review it
> before using the installer elsewhere. `mm` stands for **Mac Manager**.

## Install

```bash
mkdir -p ~/Repositories/dev
git clone https://github.com/tommiec/mac-workstation.git ~/Repositories/dev/mac-workstation
bash ~/Repositories/dev/mac-workstation/scripts/mm_install.sh
```

Install the Command Line Tools first with `xcode-select --install` if `git` is
not yet available.

`mm install` installs the `Brewfile`, creates `~/.local/bin/mm`, configures Git
hygiene, starts the managed Ollama service and registers weekly maintenance.
It also adds `~/.local/bin` to `PATH` through `~/.zshrc` when needed.

Update the checkout with:

```bash
git -C ~/Repositories/dev/mac-workstation pull --ff-only
```

Script changes are active immediately. Rerun `mm install` only after changing
installer-managed setup such as the `Brewfile`, LaunchAgents or `mm` wrapper.

## Commands

| Command | Purpose |
|---|---|
| `mm maintain` | Interactive Homebrew, macOS, backup and cleanup maintenance |
| `mm backup` | Back up SSH, GPG and Git identity in one vault session |
| `mm restore` | Preview a restore; add `--apply` to write changes |
| `mm doctor` | Audit the installed setup and report drift |
| `mm selftest` | Test Git guards and backup/restore safeguards in a sandbox |
| `mm triage <file>` | Inspect a suspicious file |
| `mm install` | Install or refresh managed setup |
| `mm auto` | Run the non-interactive weekly maintenance now |
| `mm help` | Show command help |

Automatic maintenance runs every Saturday at 02:00 through a user
LaunchAgent. Failures return a nonzero status; informational drift does not.

## Layout

```text
~/Repositories/dev/mac-workstation   source and runtime
~/.local/bin/mm                      CLI entrypoint
~/Library/Logs/mac_manager/          logs and run status
```

GitHub is the canonical source. iCloud Drive is used only for the encrypted
backup vault and an optional Downloads shortcut.

## Maintenance and diagnostics

`mm maintain` updates Homebrew formulae, offers optional cask upgrades, flushes
DNS, detects macOS updates, offers `mm backup`, and can clear QuickTime's recent
document history. macOS updates are opened in System Settings so authentication
never passes through the terminal.

`mm doctor` is read-only. It checks installation drift, Homebrew, Ollama, Git,
SSH hygiene, logs and recent script results. `mm selftest` complements it by
proving that safety checks reject invalid states.

## Ollama

`mm install` manages Ollama through
`~/Library/LaunchAgents/local.mac-manager.ollama.plist`, installs the models
declared in `scripts/mm_common.sh`, and listens on `0.0.0.0:11434` for LAN use.

The Ollama API has no authentication. Use it only on a trusted network, never
forward port `11434`, and stop the service before joining an untrusted network:

```bash
launchctl bootout "gui/$(id -u)/local.mac-manager.ollama"
```

The Mac must be logged in and awake. `mm auto` restarts the service after an
Ollama upgrade when the running server and installed CLI differ.

## Git identity and hooks

`mm install` configures shared excludes, managed hooks and
`user.useConfigOnly=true`. Commit identity is selected per forge from:

```text
~/.config/git/git-profile.conf
```

The real profile is machine-local because it contains personal data and forge
URLs. `configs/git-profile.conf.example` documents its format. `mm backup`
stores it in the encrypted vault; `mm restore` retrieves it. Managed hooks
reject unknown remotes, repository-level identity overrides and outgoing
commits with the wrong author. The full local policy lives in
`~/Repositories/GIT.md`.

## File triage

```bash
mm triage ~/Downloads/example.exe
```

The command reports file type and SHA-256, checks VirusTotal when `vt` is
configured, compares extension and magic bytes, and extracts a small set of
useful indicators. It never replaces a full malware-analysis environment.

## Secrets and backups

Keep API keys out of dotfiles. The shared helper can store and retrieve a value
through macOS Keychain:

```bash
source ~/Repositories/dev/mac-workstation/scripts/mm_common.sh
keychain_set "ANTHROPIC_API_KEY"
keychain_get "ANTHROPIC_API_KEY"
```

Recovery material lives in one encrypted sparsebundle:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/Secure Vault/Secrets.sparsebundle
```

`mm backup` mounts it once and writes:

- `ssh-backup/`: a mirror of `~/.ssh`
- `gpg-backup/`: portable exports, a full `~/.gnupg` copy and archives
- `git-profile/`: the machine-local Git identity
- `pem-archive/`: manual storage; created if absent, never synced or restored

Every backup is verified after writing. Files are compared by checksum and
relative path; missing, changed or unexpected payload files fail the run.
Directory metadata and Finder's `.DS_Store` are ignored. GPG verification
covers the source snapshot, `latest` and the extracted archive.

The vault password is handled by macOS and is never read or logged by the
scripts. After a successful backup, let iCloud Drive finish syncing before
shutting down or editing the vault elsewhere.

Use section flags when needed:

```bash
mm backup --ssh
mm backup --gpg
mm backup --git-profile
```

## Restore

`mm restore` is a dry run by default. For a complete recovery procedure, see
[Restore on a new Mac](docs/restore.md).

```bash
mm restore
mm restore --apply
```

For an urgent SSH-only restore before installing everything:

```bash
bash ~/Repositories/dev/mac-workstation/scripts/mm_restore.sh --ssh
bash ~/Repositories/dev/mac-workstation/scripts/mm_restore.sh --ssh --apply
```

## Downloads and iCloud Drive

`~/Downloads` remains local for browsers and AirDrop. When iCloud Drive exists,
`mm install` creates `~/Downloads/iCloud Downloads` as a symlink to iCloud
Drive's `Downloads` folder without replacing an existing entry. Cleanup tools
that follow symlinks, such as `find -L`, can cross into iCloud Drive.

## License

MIT — Thomas Coppens

## AI usage

AI was used extensively to design and write the shell scripts, analyze errors,
suggest improvements and help structure the documentation. I defined the
requirements, reviewed the changes, tested the resulting workflows and remain
responsible for the project and its maintenance.
