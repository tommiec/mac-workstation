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
| `mm_maintain.sh` | Run maintenance now: Homebrew, DNS flush, macOS updates |
| `mm_doctor.sh` | Health checks and diagnostics (`mm doctor`) |
| `mm_triage.sh` | Quick file/malware triage with hash, VirusTotal and strings (`mm triage`) |
| `mm_common.sh` | Shared configuration and helpers (app list lives here) |

## How it works

Scripts are managed using a **repo + symlink + CLI model**:

```
~/Repositories/mac-workstation          → source of truth (git repo)
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
git clone https://github.com/tommiec/mac-workstation.git ~/Repositories/mac-workstation
bash ~/Repositories/mac-workstation/scripts/mm_install.sh
```

The installer will:
- set up Homebrew (if needed)
- install all apps from `MANAGED_CASKS` and `CLI_TOOLS` in `mm_common.sh`
- create the symlink under `~/Scripts/mac-workstation`
- install the `mm` command in `~/Scripts/bin`
- register the weekly launchd job

To update later:

```bash
cd ~/Repositories/mac-workstation
git pull --ff-only
```

Normal script changes are active after `git pull` because `~/Scripts/mac-workstation` is a symlink to the repo. Run `mm install` only if you changed installer-managed setup: the app list, LaunchAgent schedule, or `mm` wrapper.

### iCloud bootstrap

If you already have a synced copy in iCloud Drive (my personal fallback), you can run the installer from there instead:

```bash
bash ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts/mac-workstation/scripts/mm_install.sh
```

Useful on a new Mac before Git is configured. The installer copies scripts from wherever you run `mm_install.sh` from, so both the repo and the iCloud copy work as a source.

## Usage

**Automatic** — runs every Saturday at 02:00 via launchd.

**Commands:**

```bash
mm auto      # run automated maintenance now
mm maintain  # run maintenance now
mm install   # re-run setup
mm doctor    # check system health
mm triage <file>  # inspect a suspicious file
mm help      # show available commands
```

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

API keys and tokens should never be stored as plain text in dotfiles. The recommended approach on macOS is to use the system Keychain as the single source of truth — iCloud Keychain then provides automatic encrypted backup across your Apple devices.

`mm_common.sh` exposes two helpers for this:

```bash
keychain_set "ANTHROPIC_API_KEY" "sk-ant-..."   # store once
keychain_get "ANTHROPIC_API_KEY"                 # retrieve
```

In `~/.zshrc`, load the key at shell startup instead of hardcoding it:

```bash
export ANTHROPIC_API_KEY="$(keychain_get ANTHROPIC_API_KEY 2>/dev/null)"
```

`mm doctor` checks for violations:

- **Plain-text secrets in dotfiles** — scans `~/.zshrc`, `~/.zprofile`, `~/.bashrc`, `~/.bash_profile`, and `~/.profile` for variable assignments whose names contain `KEY`, `TOKEN`, `SECRET`, or `PASSWORD` and whose value appears to be a literal string (not a `$(...)` or `${...}` expression). Values are masked in the output.
- **SSH private key permissions** — all private keys in `~/.ssh` (excluding `.pub`, `known_hosts`, `config`, and `authorized_keys`) must have permissions `600`. Warns with the exact `chmod` command if not.
- **`~/.ssh` directory permissions** — the folder itself should be `700`.

SSH private keys should always be protected with a passphrase. macOS stores the passphrase in Keychain automatically when you first use the key, so you only type it once.

## Notes

- Uses a LaunchAgent (user context, no root daemon)
- Writes logs and last-run status under `~/Library/Logs/mac_manager/`
- Safe to re-run `mm install` at any time, but usually only needed after installer-managed setup changes
- `mm doctor` can be used to validate the setup and inspect the last recorded run for each script

## License

MIT — Thomas Coppens
