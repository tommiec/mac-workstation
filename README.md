# mac-maintenance

Personal macOS maintenance scripts using Homebrew and launchd.

## Why this exists

A consistent, low-effort way to keep a Mac up to date — without forgetting updates, letting Homebrew drift, or doing cleanup ad hoc.

One-time setup. Runs automatically. Manual control when needed.

## Scripts

| Script | Purpose |
|---|---|
| `mac_install.sh` | One-time setup on a new Mac |
| `mac_auto.sh` | Automated weekly maintenance (launchd) |
| `mac_manual.sh` | Manual diagnostics and updates |
| `mac_common.sh` | Shared configuration and helpers |

## How it works

Scripts are stored in **iCloud Drive** (source) and deployed to **Application Support** (runtime) by `mac_install.sh`. launchd always runs the local copy — never the iCloud version.

```
iCloud Drive/Scripts/mac-maintenance/   → edit here
~/Library/Application Support/mac-maintenance/  → runs here
~/Library/Logs/mac_maintenance/         → logs here
```

## Installation

Clone into iCloud Drive, then run once on a new Mac:

```bash
mkdir -p ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts
cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts
git clone https://github.com/tommiec/mac-maintenance.git
```

```bash
bash ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts/mac-maintenance/scripts/mac_install.sh
```

This installs Homebrew packages, copies scripts to Application Support, and registers the weekly launchd agent.

## Usage

**Automatic** — runs every Saturday at 02:00 via launchd, no action needed.

**Manual:**
```bash
bash ~/Library/Application\ Support/mac-maintenance/mac_manual.sh
```

**Update:**
```bash
cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts/mac-maintenance
git pull
bash scripts/mac_install.sh
```

## Notes

- Runs as LaunchAgent (user context, no root daemon)
- Safe to re-run `mac_install.sh` at any time

## License

MIT — Thomas Coppens