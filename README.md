# mac-maintenance

Automated macOS maintenance scripts using Homebrew and launchd.

## Why this exists

Maintaining a macOS development machine often ends up being inconsistent:

- updates are forgotten or postponed
- Homebrew packages drift out of date
- system cleanup is done manually (or not at all)
- maintenance scripts grow ad hoc and unreliable

This project was created to solve that by providing a **simple, structured and reliable maintenance workflow**:

- one-time setup (`mac_install.sh`)
- safe, automated routine tasks (`mac_auto.sh`)
- controlled, manual maintenance (`mac_manual.sh`)

The goal is not to over-engineer, but to have a **minimal, predictable system that just works**.

## Overview

| Script | Purpose |
|---|---|
| `mac_install.sh` | One-time setup: installs apps, copies scripts, registers launchd agent |
| `mac_auto.sh` | Automated weekly maintenance via launchd |
| `mac_manual.sh` | Manual diagnostics and optional update installation |
| `mac_common.sh` | Shared configuration, helpers and functions |

## Features

- Homebrew package and cask management
- Automated weekly maintenance via launchd (Saturday 02:00)
- macOS update detection with notifications
- Optional interactive update installation
- Cache cleanup
- System diagnostics (`brew doctor`, DNS flush)
- macOS notifications on start, completion and when updates are found

## Requirements

- macOS (Apple Silicon or Intel)
- Homebrew (installed automatically if missing)
- iCloud Drive (recommended for storing source scripts)

## Installation

Store the scripts in iCloud Drive, then run `mac_install.sh` once on a new Mac:

```bash
bash ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts/mac/mac_install.sh
```

This will:

1. Copy all scripts to `~/Library/Application Support/mac-maintenance/`
2. Install Homebrew if not present
3. Install all apps defined in `MANAGED_CASKS` and `CLI_TOOLS`
4. Register `mac_auto.sh` as a weekly launchd agent

## Usage

### Automatic maintenance

Runs automatically every Saturday at 02:00 via launchd. No action required after installation.

Logs are written to `~/Library/Logs/mac_maintenance/`.

### Manual maintenance

```bash
bash ~/Library/Application\ Support/mac-maintenance/mac_manual.sh
```

Requires sudo (prompted once at startup). Runs `brew doctor`, flushes DNS cache, and checks for macOS updates with the option to install them interactively.

### Updating scripts

Edit the source scripts in iCloud Drive, then re-run `mac_install.sh` to deploy the updated versions.

## Structure

```
iCloud Drive/Scripts/mac/       → source scripts (edit here)
~/Library/Application Support/
  mac-maintenance/              → runtime scripts (deployed by mac_install.sh)
~/Library/Logs/
  mac_maintenance/              → log output
~/Library/LaunchAgents/
  local.mac.auto-maintenance.plist  → launchd schedule
```

## Notes

- Scripts run in user context (LaunchAgent, no root daemon)
- Safe to re-run `mac_install.sh` at any time
- iCloud source scripts are never executed directly by launchd — only the local copies in `Application Support` are used

## Author

Created by Thomas Coppens.  
If you find this useful, feel free to star the repo ⭐

## License

MIT