#!/bin/bash
# =========================================================
# mac_install.sh
# Setup script — installeert apps en configureert automation
#
# Gebruik (éénmalig op nieuwe Mac, vanuit iCloud Drive):
#   bash ~/Library/Mobile\ Documents/com~apple~CloudDocs\
#        /Scripts/mac/mac_install.sh
#
# Wat dit script doet:
#   1. Kopieert alle scripts naar:
#        ~/Library/Application Support/mac-maintenance/
#   2. Installeert Homebrew indien nodig
#   3. Installeert alle apps uit MANAGED_CASKS en CLI_TOOLS
#   4. Registreert mac_auto.sh als wekelijkse launchd-agent
#        (elke zaterdag om 02:00)
#
# Na installatie:
#   Manueel onderhoud:
#     bash ~/Library/Application\ Support/mac-maintenance/\
#          mac_manual.sh
# =========================================================

set -o pipefail
set -u

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$HOME/Library/Application Support/mac-maintenance"

mkdir -p "$BASE_DIR"

echo "── 🚀 Installatie gestart ──"

# ── Scripts kopiëren ─────────────────

for f in mac_common.sh mac_auto.sh mac_manual.sh mac_install.sh; do
    cp "$SRC_DIR/$f" "$BASE_DIR/$f"
done

chmod +x "$BASE_DIR"/*.sh

source "$BASE_DIR/mac_common.sh"
mkdir -p "$LOG_DIR"

# ── Homebrew ─────────────────────────

if ensure_brew; then
    log_ok "Homebrew beschikbaar."
else
    log_warn "Homebrew installatie mislukt"
    exit 1
fi

run_step "brew update" brew update

# ── Install apps ─────────────────────

for pkg in "${MANAGED_CASKS[@]}"; do
    brew list --cask "$pkg" &>/dev/null \
        && log_ok "$pkg al aanwezig" \
        || run_step "$pkg installeren" brew install --cask "$pkg"
done

for pkg in "${CLI_TOOLS[@]}"; do
    brew list "$pkg" &>/dev/null \
        && log_ok "$pkg al aanwezig" \
        || run_step "$pkg installeren" brew install "$pkg"
done

run_step "brew cleanup" brew cleanup

# ── LaunchAgent ─────────────────────

write_auto_launch_agent

if load_auto_launch_agent; then
    log_ok "Auto-maintenance ingepland voor zaterdag $(printf '%02d:%02d' "$AUTO_HOUR" "$AUTO_MINUTE")"
else
    log_warn "LaunchAgent laden mislukt"
fi

summary_print