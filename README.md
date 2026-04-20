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

⚠️ The installer copies scripts from the location it is executed from into `~/Repositories/mac-maintenance`.

→ The installer copies scripts from the directory you run `mac_install.sh` from into `~/Repositories/mac-maintenance`. If you run it from iCloud, that copy is used; if you run it from the repo, the repo is used.

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
```

## Notes

- Uses a LaunchAgent (user context, no root daemon)
- Safe to re-run `mm install` at any time
- `mm doctor` can be used to validate the setup

## License

MIT — Thomas Coppens