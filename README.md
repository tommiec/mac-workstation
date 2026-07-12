# mac-workstation

My personal macOS workstation setup: Homebrew tooling, scheduled maintenance, diagnostics, and file/security triage.

## Why this exists

A consistent, low-effort way to bootstrap my Mac, keep core tooling maintained, and support day-to-day IT, DevOps, AI, and security work.

One-time setup. Runs automatically. Manual control when needed.

> **Using this yourself?** The app list in `mm_common.sh` (`MANAGED_CASKS`, `CLI_TOOLS`) is mine. Fork the repo and replace those lists with your own before running the installer.
>
> `mm` stands for **Mac Manager**.

## Scripts

| Script | Purpose |
|---|---|
| `mm_install.sh` | Bootstrap setup (repo, symlink, CLI, launchd) |
| `mm_auto.sh` | Automated weekly maintenance (launchd) |
| `mm_maintain.sh` | Run maintenance now: Homebrew, optional cask upgrades, DNS flush, macOS updates, optional SSH backup, optional QuickTime history cleanup |
| `mm_doctor.sh` | Health checks and diagnostics (`mm doctor`) |
| `mm_triage.sh` | Quick file/malware triage with hash, VirusTotal and strings (`mm triage`) |
| `mm_backup_ssh.sh` | Backup `~/.ssh` to an encrypted iCloud sparsebundle (called by `mm maintain`) |
| `mm_backup_gpg.sh` | Backup GPG keys, ownertrust and `~/.gnupg` to the encrypted iCloud sparsebundle |
| `mm_common.sh` | Shared configuration and helpers (app list lives here) |

## How it works

Scripts are managed using a **repo + symlink + CLI model**:

```
~/Repositories/dev/mac-workstation          → source of truth (git repo)
~/Scripts/mac-workstation               → symlink to repo
~/Scripts/bin/mm                        → CLI entrypoint
~/Library/Logs/mac_manager/             → logs
```

- The repo contains all scripts and is version-controlled
- A symlink provides a stable runtime path
- The `mm` command provides a simple interface
- launchd runs the auto-maintenance script from the symlinked location

## Installation

Clone the repo and run the installer once:

```bash
git clone https://github.com/tommiec/mac-workstation.git ~/Repositories/dev/mac-workstation
bash ~/Repositories/dev/mac-workstation/scripts/mm_install.sh
```

The installer will:
- set up Homebrew (if needed)
- install all apps from `MANAGED_CASKS` and `CLI_TOOLS` in `mm_common.sh`
- create the symlink under `~/Scripts/mac-workstation`
- install the `mm` command in `~/Scripts/bin`
- configure global Git excludes and a local Git hooks path
- register the weekly launchd job

To update later:

```bash
cd ~/Repositories/dev/mac-workstation
git pull --ff-only
```

Normal script changes are active after `git pull` because `~/Scripts/mac-workstation` is a symlink to the repo. Run `mm install` only if you changed installer-managed setup: the app list, LaunchAgent schedule, or `mm` wrapper.

### iCloud bootstrap

If you already have a synced copy in iCloud Drive (my personal fallback), you can run the installer from there instead:

```bash
bash ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts/mac-workstation/scripts/mm_install.sh
```

Useful on a new Mac before Git is configured. The installer copies scripts from wherever you run `mm_install.sh` from, so both the repo and the iCloud copy work as a source.

### Local Git config bootstrap

`mm install` configures the machine-wide Git hygiene baseline:

- `configs/git-ignore-global` is copied to `~/.config/git/ignore`
- Git is configured with `core.excludesFile=~/.config/git/ignore`
- Git is configured with `core.hooksPath=~/.config/git/hooks`

That baseline is intentionally small and public-safe. It keeps local workspace
files out of Git, but it does not store personal hook logic or detailed local
ignore rules in this repository.

For private machine-specific Git rules, `mm install` also looks for an optional
iCloud overlay:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/Scripts/git/
  ignore.local
  hooks/
```

When present:

- `ignore.local` is copied to `~/.config/git/ignore.local`
- files in `hooks/` are copied to `~/.config/git/hooks/`
- hook files are made executable
- `ignore.local` is appended to the generated `~/.config/git/ignore`

This keeps private commit-message checks, personal tooling excludes, and other
machine-local Git hygiene recoverable after a reinstall without storing their
contents in this public repo. `mm doctor` verifies that the global exclude file,
hooks path, optional iCloud source, and local `commit-msg` hook are present.

## Usage

**Automatic** — runs every Saturday at 02:00 via launchd.

**Commands:**

```bash
mm auto      # run automated maintenance now
mm maintain  # run maintenance now (interactive prompts)
mm install   # re-run setup
mm doctor    # check system health
mm triage <file>  # inspect a suspicious file
mm help      # show available commands
```

`mm maintain` reports Homebrew casks installed outside `MANAGED_CASKS`, then asks before taking optional actions: upgrading all outdated Homebrew casks, installing macOS updates, backing up `~/.ssh` and GPG keys/trust to the encrypted iCloud vault, and clearing QuickTime Player's recent documents history. The QuickTime cleanup removes QuickTime's app-specific recent-document shared-file-list entries and legacy QuickTime preference keys. It does not delete media files and does not clear system-wide macOS Recent Items.

## File triage

Use `mm triage` for a quick first look at a suspicious file:

```bash
mm triage ~/Downloads/example.exe
```

The command:
- identifies the file type using `file`
- calculates the SHA256 hash
- looks up the hash in VirusTotal when the `vt` CLI is available
- shows a short hex preview
- checks magic bytes against common file types
- flags mismatches between file extension and detected content
- extracts quick indicators such as URLs, IPs, shell commands and suspicious strings
- prints a simple triage score
- opens extracted strings in `less` for manual review

The installer installs `virustotal-cli`. The triage script uses the CLI command `vt` for lookups, so configure the `vt` CLI with your VirusTotal API key first. The string view opens in `less`; press `q` to exit it.

## Secrets & SSH keys

Avoid storing API keys and tokens as plain text in dotfiles. On macOS, Keychain or Apple Passwords is a better place for them.

For one-off Keychain use, source the helper file first:

```bash
source ~/Scripts/mac-workstation/scripts/mm_common.sh
keychain_set "ANTHROPIC_API_KEY"   # store once; prompts for the secret
keychain_get "ANTHROPIC_API_KEY"   # retrieve
```

In `~/.zshrc`, load the key directly from Keychain instead of hardcoding it:

```bash
export ANTHROPIC_API_KEY="$(security find-generic-password -a "$USER" -s ANTHROPIC_API_KEY -w 2>/dev/null)"
```

`mm doctor` scans shell dotfiles for likely plain-text secrets and masks their values in the output. It also shows an inventory of SSH private keys in `~/.ssh` — name, type, bits, fingerprint, and modification date — and warns on loose directory/file permissions, DSA keys, and short RSA keys (< 3072b). Only group or other access triggers a warning; common safe modes are `600` and `400`. For SSH trust awareness, it also summarizes `known_hosts` with visible and hashed host patterns, modification date, and a small visible sample when available.

Use passphrases for SSH private keys. macOS can remember those passphrases in Keychain.

### Encrypted secrets vault

For secrets that should be recoverable on a new Mac but should not live as plain files in iCloud Drive, this setup uses one encrypted sparsebundle:

```bash
~/Library/Mobile Documents/com~apple~CloudDocs/Secure Vault/Secrets.sparsebundle
```

macOS asks for the vault password each time it needs to be mounted. On the first run it also asks you to choose that password — store it in your password manager. The script never stores or logs the vault password.

Inside the mounted vault, SSH, GPG and PEM material have different lifecycles:

```text
ssh-backup/
gpg-backup/
pem-archive/
```

`ssh-backup/` is managed by the optional SSH backup prompt in `mm maintain`. It mirrors `~/.ssh` into the encrypted vault and may overwrite that backup on future runs.

`gpg-backup/` is managed by the optional GPG backup prompt in `mm maintain`. It stores `latest/portable/` exports (`public-keys.asc`, `secret-keys.asc`, `ownertrust.txt`, and `secret-keys-list.txt`), `latest/full-gnupg/.gnupg/`, and timestamped archives under `archives/`.

To restore the portable GPG backup on a new Mac:

```bash
cd "/Volumes/Secrets/gpg-backup/latest/portable"
gpg --import public-keys.asc
gpg --import secret-keys.asc
gpg --import-ownertrust ownertrust.txt
```

If you need an exact full restore instead, copy `gpg-backup/latest/full-gnupg/.gnupg/` back to `~/.gnupg` while GPG is not running, then restart GPG/GPG Suite.

`pem-archive/` is manual storage for PEM/private-key files that should live only inside the encrypted vault. The SSH backup command creates the folder but never syncs, cleans, or overwrites it.

Unmount the vault after use and let iCloud Drive finish syncing before shutting down or editing it elsewhere.

## Notes

- Uses a LaunchAgent (user context, no root daemon)
- Writes logs and last-run status under `~/Library/Logs/mac_manager/`
- Safe to re-run `mm install` at any time, but usually only needed after installer-managed setup changes
- `mm doctor` can be used to validate the setup and inspect the last recorded run for each script
- Global Git hygiene is installed by `mm install`: shared excludes come from
  this repo, while machine-local excludes and hooks live under `~/.config/git`
  and are not stored here.

## License

MIT — Thomas Coppens

## AI usage

AI was used as a sounding board for shell-scripting choices, error analysis and documentation structure. The design, implementation, validation and maintenance are mine.
