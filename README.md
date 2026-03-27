# mac-maintenance

Automated macOS maintenance scripts using Homebrew and launchd.

## Why this exists

Maintaining a macOS development machine often ends up being inconsistent:

- updates are forgotten or postponed  
- Homebrew packages drift out of date  
- system cleanup is done manually (or not at all)  
- maintenance scripts grow ad hoc and unreliable  

This project was created to solve that by providing a **simple, structured and reliable maintenance workflow**:

- one-time setup (`install`)
- safe, automated routine tasks (`auto`)
- controlled, manual maintenance (`manual`)

The goal is not to over-engineer, but to have a **minimal, predictable system that just works**.

## Overview

This project provides a lightweight maintenance framework for macOS:

- `mac_install.sh` → initial setup and configuration  
- `mac_auto.sh` → automated weekly maintenance  
- `mac_manual.sh` → manual diagnostics and updates  
- `mac_common.sh` → shared logic and configuration  

## Features

- Homebrew package management
- Automated weekly maintenance via launchd
- macOS update detection
- Optional manual update installation
- Cache cleanup
- System diagnostics (brew doctor, DNS flush)
- macOS notifications

## Installation

Clone the repository:

git clone https://github.com/YOUR_USERNAME/mac-maintenance.git
cd mac-maintenance/scripts
bash mac_install.sh

This will:

- Install required software
- Copy scripts to:
  ~/Library/Application Support/mac-maintenance
- Configure automatic maintenance via launchd

## Usage

### Automatic maintenance

Runs weekly (Saturday 02:00) via launchd.

### Manual maintenance

bash ~/Library/Application\ Support/mac-maintenance/mac_manual.sh

## Structure

scripts/   → source scripts (this repo)  
runtime/   → ~/Library/Application Support/mac-maintenance  
logs/      → ~/Library/Logs/mac_maintenance  

## Notes

- Scripts run in user context (LaunchAgent)
- No root daemons are used
- Safe to run multiple times

## Author

Created by Thomas Coppens  
If you find this useful, feel free to star the repo ⭐

## License

MIT