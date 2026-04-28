# mac-maintenance

Personal macOS maintenance scripts using Homebrew and launchd.

## Why this exists

A consistent, low-effort way to keep a Mac up to date — without forgetting updates, letting Homebrew drift, or doing cleanup ad hoc.

One-time setup. Runs automatically. Manual control when needed.

## Scripts

| Script | Purpose |
|---|---|
| `mac_install.sh` | Bootstrap setup (repo, symlink, CLI, launchd) |
| `mac_auto.sh` | Automated weekly maintenance (launchd) |
| `mac_manual.sh` | Manual diagnostics and updates |
| `mac_doctor.sh` | Health checks and diagnostics (`mm doctor`) |
| `mac_triage.sh` | Quick file/malware triage with hash, VirusTotal and strings (`mm triage`) |
| `mac_common.sh` | Shared configuration and helpers |

## How it works

Scripts are managed using a **repo + symlink + CLI model**:

```
~/Repositories/mac-maintenance          → source of truth (git repo)
~/Scripts/mac-maintenance               → symlink to repo
~/Scripts/bin/mm                        → CLI entrypoint
~/Library/Logs/mac_maintenance/         → logs
```

- The repo contains all scripts and is version-controlled
- A symlink provides a stable runtime path
- The `mm` command provides a simple interface
- launchd runs the auto-maintenance script from the symlinked location

## Installation

Clone the repository and run the installer once:

```bash
git clone https://github.com/tommiec/mac-maintenance.git ~/Repositories/mac-maintenance
bash ~/Repositories/mac-maintenance/scripts/mac_install.sh
```

The installer will:
- set up Homebrew (if needed)
- install required packages
- create the symlink under `~/Scripts/mac-maintenance`
- install the `mm` command in `~/Scripts/bin`
- register the weekly launchd job

## Bootstrap options

The **GitHub repository is the source of truth** for this project. All changes should be committed there.

There are two supported ways to bootstrap a new Mac:

### Option 1 — GitHub (recommended)

```bash
git clone https://github.com/tommiec/mac-maintenance.git ~/Repositories/mac-maintenance
bash ~/Repositories/mac-maintenance/scripts/mac_install.sh
```

- Always up to date
- Preferred for first setup or clean installs

### Option 2 — iCloud Drive (convenience)

If you already have a synced copy in iCloud Drive, you can run the installer from there:

```bash
bash ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts/mac-maintenance/scripts/mac_install.sh
```

- Useful when Git is not yet configured
- Acts as a bootstrap/fallback mechanism

⚠️ The installer copies scripts from the directory you run `mac_install.sh` from into `~/Repositories/mac-maintenance`. If you run it from iCloud, that copy is used; if you run it from the repo, the repo is used. This keeps bootstrap flexible for different setup scenarios.

To avoid drift:
- treat GitHub as the canonical source
- keep any iCloud copy in sync (or regenerate it from the repo)

## Usage

**Automatic** — runs every Saturday at 02:00 via launchd.

**Manual commands:**

```bash
mm auto     # run automated maintenance now
mm manual   # run manual diagnostics and updates
mm install  # re-run setup
mm doctor   # check system health
mm triage <file>  # inspect a suspicious file
mm help     # show available commands
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

The installer installs both the VirusTotal GUI app and `virustotal-cli`. The triage script uses the CLI command `vt` for lookups, so configure the `vt` CLI with your VirusTotal API key first. The string view opens in `less`; press `q` to exit it.

## Notes

- Uses a LaunchAgent (user context, no root daemon)
- Writes logs and last-run status under `~/Library/Logs/mac_maintenance/`
- Safe to re-run `mm install` at any time
- `mm doctor` can be used to validate the setup and inspect the last recorded run for each script

## License

MIT — Thomas Coppens
