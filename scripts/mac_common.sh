#!/bin/bash
# =========================================================
# mac_common.sh
# Gedeelde functies, config en helpers
#
# Niet rechtstreeks uitvoeren — wordt gesourced door de
# andere scripts.
#
# Workflow:
#   1. Bewaar alle scripts in iCloud Drive
#   2. Voer mac_install.sh éénmalig uit op een nieuwe Mac
#   3. Scripts worden gekopieerd naar:
#        ~/Library/Application Support/mac-maintenance/
#   4. launchd draait mac_auto.sh automatisch elke zaterdag
#        om 02:00
#   5. Manueel onderhoud: bash .../mac_manual.sh
#   6. Scripts bijwerken: aanpassen in iCloud, daarna
#        mac_install.sh opnieuw uitvoeren
# =========================================================

# ── Logging ─────────────────────────────────────────────

STEP_OK=0
STEP_WARN=0
SUMMARY=()

log_ok()   { echo "   ✅ $*"; SUMMARY+=("✅ $*"); ((STEP_OK++)) || true; }
log_warn() { echo "   ⚠️  $*"; SUMMARY+=("⚠️  $*"); ((STEP_WARN++)) || true; }
log_info() { echo "   ℹ️  $*"; }

run_step() {
    local msg="$1"; shift
    if "$@"; then
        log_ok "$msg"
    else
        log_warn "$msg mislukt"
    fi
}

summary_print() {
    echo ""
    echo "── 📊 Samenvatting ───────────────────────────────"
    printf '%s\n' "${SUMMARY[@]}"
    echo ""
    echo "   Resultaat: $STEP_OK OK / $STEP_WARN waarschuwingen"
}

notify_user() {
    local title="$1"
    local message="$2"
    /usr/bin/osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\""
}

# ── Config ─────────────────────────────────────────────

BASE_DIR="$HOME/Library/Application Support/mac-maintenance"
LOG_DIR="$HOME/Library/Logs/mac_maintenance"

LAUNCH_AGENT_LABEL="local.mac.auto-maintenance"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"

# launchd: 0=zondag ... 6=zaterdag
AUTO_WEEKDAY=6
AUTO_HOUR=2
AUTO_MINUTE=0

MANAGED_CASKS=(
  visual-studio-code
  intellij-idea
  postman
  gitkraken
  github
  cyberduck
  mysqlworkbench
  visual-paradigm
  rectangle
  vlc
  onyx
  appcleaner
)

CLI_TOOLS=(
  nmap
)

# ── Homebrew ───────────────────────────────────────────

ensure_brew() {
    if ! command -v brew &>/dev/null; then
        echo "Homebrew installeren..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
    fi
    return 0
}

# ── LaunchAgent ────────────────────────────────────────

write_auto_launch_agent() {
    mkdir -p "$(dirname "$LAUNCH_AGENT_PATH")"

    cat > "$LAUNCH_AGENT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCH_AGENT_LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$BASE_DIR/mac_auto.sh</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>$AUTO_WEEKDAY</integer>
        <key>Hour</key>
        <integer>$AUTO_HOUR</integer>
        <key>Minute</key>
        <integer>$AUTO_MINUTE</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>$LOG_DIR/launchd_auto.out</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/launchd_auto.err</string>
</dict>
</plist>
EOF
}

load_auto_launch_agent() {
    /bin/launchctl bootout "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
    /bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH" || return 1

    if /bin/launchctl print "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}