#!/bin/bash
# =========================================================
# mac_common.sh
# Shared configuration, paths and helper functions
#
# Do not run directly — sourced by the other scripts.
#
# Supported bootstrap models:
#
# 1. GitHub / repo (recommended)
#    - Source of truth: ~/Repositories/mac-maintenance
#    - Runtime path:     ~/Scripts/mac-maintenance -> repo symlink
#    - CLI entrypoint:   ~/Scripts/bin/mm
#
# 2. iCloud Drive (bootstrap / fallback)
#    - Optional synced copy under:
#        ~/Library/Mobile Documents/com~apple~CloudDocs/Scripts/mac-maintenance/
#    - Useful on a new Mac before Git is configured
#    - Can be refreshed from the repo when needed
#
# In normal use, GitHub/repo remains the canonical source.
# =========================================================

# ── Config ──────────────────────────────────────────────
# SCRIPTS_DIR wijst naar de scripts-map binnen de repo.
# Alle andere scripts sourcen dit bestand en erven SCRIPTS_DIR.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/Library/Logs/mac_maintenance"
REPO_ROOT="$HOME/Repositories/mac-maintenance"
SCRIPTS_ROOT="$HOME/Scripts"
SYMLINK_PATH="$SCRIPTS_ROOT/mac-maintenance"
BIN_DIR="$SCRIPTS_ROOT/bin"
MM_PATH="$BIN_DIR/mm"
ICLOUD_SCRIPTS_ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Scripts"
ICLOUD_BOOTSTRAP_ROOT="$ICLOUD_SCRIPTS_ROOT/mac-maintenance"
ICLOUD_BOOTSTRAP_DIR="$ICLOUD_BOOTSTRAP_ROOT/scripts"

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
  monitorcontrol
  virtualbox
  marsanne/cask/virustotal
)

CLI_TOOLS=(
  nmap
  virustotal-cli
)

# ── Logging ─────────────────────────────────────────────

STEP_OK=0
STEP_WARN=0
SUMMARY=()

log_ok() {
    echo "   ✅ $*"
    SUMMARY+=("✅ $*")
    (( STEP_OK++ )) || true
}

log_warn() {
    echo "   ⚠️  $*"
    SUMMARY+=("⚠️  $*")
    (( STEP_WARN++ )) || true
}

log_info() {
    echo "   ℹ️  $*"
}

# Voert een commando uit en logt het resultaat op basis van exit code.
# Gebruik: run_step "beschrijving" commando [args...]
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
    if [[ "${#SUMMARY[@]}" -eq 0 ]]; then
        echo "   (geen stappen geregistreerd)"
    else
        printf '%s\n' "${SUMMARY[@]}"
    fi
    echo ""
    echo "   Resultaat: $STEP_OK OK / $STEP_WARN waarschuwingen"
}

notify_user() {
    local title="$1"
    local message="$2"
    /usr/bin/osascript \
        -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\""
}

# ── Homebrew ────────────────────────────────────────────

ensure_brew() {
    if ! command -v brew &>/dev/null; then
        echo "Homebrew installeren..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            || return 1
    fi
    return 0
}

# ── LaunchAgent ─────────────────────────────────────────

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
        <string>$SCRIPTS_DIR/mac_auto.sh</string>
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

sync_scripts_to_icloud() {
    if [[ ! -d "$ICLOUD_SCRIPTS_ROOT" ]]; then
        log_warn "iCloud Scripts-map niet gevonden, sync overgeslagen"
        return 0
    fi

    mkdir -p "$ICLOUD_BOOTSTRAP_DIR"

    if rsync -av --delete "$SCRIPTS_DIR/" "$ICLOUD_BOOTSTRAP_DIR/" >/dev/null 2>&1; then
        log_ok "iCloud bootstrap copy bijgewerkt"
    else
        log_warn "iCloud bootstrap copy bijwerken mislukt"
        return 1
    fi
}