#!/bin/bash
# =========================================================
# mm_common.sh
# Shared configuration, paths and helper functions
#
# Do not run directly — sourced by the other scripts.
#
# Setup model:
#   Source of truth: ~/Repositories/dev/mac-workstation  (git repo)
#   Runtime path:    ~/Scripts/mac-workstation            (symlink to repo)
#   CLI entrypoint:  ~/Scripts/bin/mm
#
# iCloud Drive copy is a personal bootstrap fallback for new Macs.
# GitHub remains the canonical source.
# =========================================================

# ── Config ──────────────────────────────────────────────
# SCRIPTS_DIR points to the scripts directory inside the repo.
# All other scripts source this file and inherit SCRIPTS_DIR.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/Library/Logs/mac_manager"
SCRIPT_STATUS_DIR="$LOG_DIR/status"
REPO_ROOT="$HOME/Repositories/dev/mac-workstation"
CONFIGS_DIR="$REPO_ROOT/configs"
LOCAL_GIT_HOOKS_DIR="$HOME/.config/git/hooks"
LOCAL_GIT_EXCLUDES="$HOME/.config/git/ignore.local"
SCRIPTS_ROOT="$HOME/Scripts"
SYMLINK_PATH="$SCRIPTS_ROOT/mac-workstation"
BIN_DIR="$SCRIPTS_ROOT/bin"
MM_PATH="$BIN_DIR/mm"
ICLOUD_SCRIPTS_ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Scripts"
ICLOUD_BOOTSTRAP_ROOT="$ICLOUD_SCRIPTS_ROOT/mac-workstation"
ICLOUD_BOOTSTRAP_DIR="$ICLOUD_BOOTSTRAP_ROOT/scripts"
ICLOUD_GIT_CONFIG_ROOT="$ICLOUD_SCRIPTS_ROOT/git"

LAUNCH_AGENT_LABEL="local.mac-manager.auto-maintenance"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"
LEGACY_LAUNCH_AGENT_LABEL="local.mac.auto-maintenance"
LEGACY_LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/${LEGACY_LAUNCH_AGENT_LABEL}.plist"

# launchd: 0=Sunday ... 6=Saturday
AUTO_WEEKDAY=6
AUTO_HOUR=2
AUTO_MINUTE=0

MANAGED_CASKS=(
  # Development
  dash
  github
  gitkraken
  intellij-idea
  postman
  visual-studio-code

  # AI / media
  chatgpt
  claude
  macwhisper
  vlc

  # Communication / browser
  discord
  firefox
  microsoft-teams

  # Security / networking
  balenaetcher
  cyberduck
  malwarebytes
  wireshark-app

  # System utilities
  appcleaner
  monitorcontrol
  rectangle
  utm

  # Data / modeling
  mysqlworkbench
  visual-paradigm
)

CLI_TOOLS=(
  # Development / shell productivity
  bat
  fd
  fzf
  gh
  git
  jq
  mas
  pre-commit
  ripgrep
  shellcheck
  tmux
  tree
  yq

  # Python / AI
  ollama
  pipx
  uv

  # DevOps / containers / cloud-native
  docker
  docker-compose
  trivy

  # Security / reverse engineering
  burp
  ghidra
  john-jumbo
  sqlmap
  virustotal-cli

  # Network / VPN
  nmap
  openvpn
  wget
  wireshark

  # File / archive / document tools
  dos2unix
  exiftool
  p7zip
  pandoc
  tesseract
  tesseract-lang
  weasyprint

  # Cross-platform administration
  powershell
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

record_script_result() {
    local script_name="$1"
    local exit_code="$2"
    local log_file="${3:-}"
    local status="success"
    local status_file="$SCRIPT_STATUS_DIR/$script_name.status"
    local tmp_file="$status_file.tmp"

    if [[ "$exit_code" -ne 0 ]]; then
        status="failed"
    fi

    mkdir -p "$SCRIPT_STATUS_DIR" 2>/dev/null || return 0
    if ! {
        echo "script=$script_name"
        echo "status=$status"
        echo "exit_code=$exit_code"
        echo "finished_at=$(date '+%Y-%m-%d %H:%M:%S %z')"
        echo "log_file=$log_file"
    } > "$tmp_file" 2>/dev/null; then
        return 0
    fi
    mv "$tmp_file" "$status_file" 2>/dev/null || true
}

# Runs a command and logs the result based on its exit code.
# Usage: run_step "description" command [args...]
run_step() {
    local msg="$1"; shift
    if "$@"; then
        log_ok "$msg"
    else
        log_warn "$msg failed"
    fi
}

summary_print() {
    echo ""
    echo "── 📊 Summary ───────────────────────────────────"
    if [[ "${#SUMMARY[@]}" -eq 0 ]]; then
        echo "   (no steps recorded)"
    else
        printf '%s\n' "${SUMMARY[@]}"
    fi
    echo ""
    echo "   Result: $STEP_OK OK / $STEP_WARN warning(s)"
}

notify_user() {
    local title="$1"
    local message="$2"
    /usr/bin/osascript \
        -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\""
}

# ── Keychain helpers ────────────────────────────────────
# Usage after sourcing this file:
#   keychain_get "ANTHROPIC_API_KEY"
#   keychain_set "ANTHROPIC_API_KEY"
#
# In ~/.zshrc, load a key without storing it as plain text:
#   export ANTHROPIC_API_KEY="$(security find-generic-password -a "$USER" -s ANTHROPIC_API_KEY -w 2>/dev/null)"

keychain_get() {
    security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null
}

keychain_set() {
    local service="${1:-}"
    local secret=""

    if [[ "$#" -ne 1 || -z "$service" ]]; then
        echo "Usage: keychain_set SERVICE_NAME" >&2
        return 2
    fi

    printf "Secret for %s: " "$service" >&2
    IFS= read -r -s secret
    printf "\n" >&2

    # -U updates an existing entry if present
    security add-generic-password -U -a "$USER" -s "$service" -w "$secret"
}

# ── Git global configuration ────────────────────────────
# Installs configs/git-ignore-global as ~/.config/git/ignore and sets
# core.excludesFile so all repos on this machine inherit the exclude rules.
# Optional machine-local additions live in ~/.config/git/ignore.local and
# optional hooks live in ~/.config/git/hooks; their contents are not stored in
# this public repository.

sync_local_git_config_from_icloud() {
    local hooks_src="$ICLOUD_GIT_CONFIG_ROOT/hooks"
    local hooks_dst="$LOCAL_GIT_HOOKS_DIR"

    [[ -d "$ICLOUD_GIT_CONFIG_ROOT" ]] || return 0

    mkdir -p "$(dirname "$LOCAL_GIT_EXCLUDES")" "$hooks_dst" || return 1

    if [[ -f "$ICLOUD_GIT_CONFIG_ROOT/ignore.local" ]]; then
        cp "$ICLOUD_GIT_CONFIG_ROOT/ignore.local" "$LOCAL_GIT_EXCLUDES" || return 1
    fi

    if [[ -d "$hooks_src" ]]; then
        while IFS= read -r hook_file; do
            cp "$hook_file" "$hooks_dst/$(basename "$hook_file")" || return 1
            chmod u+x "$hooks_dst/$(basename "$hook_file")" || return 1
        done < <(find "$hooks_src" -maxdepth 1 -type f -print)
    fi
}

setup_git_global() {
    local git_config_dir="$HOME/.config/git"
    local src="$CONFIGS_DIR/git-ignore-global"
    local dst="$git_config_dir/ignore"

    if [[ ! -f "$src" ]]; then
        echo "configs/git-ignore-global not found" >&2
        return 1
    fi

    mkdir -p "$git_config_dir"
    sync_local_git_config_from_icloud || return 1

    cp "$src" "$dst" || return 1
    if [[ -f "$LOCAL_GIT_EXCLUDES" ]]; then
        {
            echo ""
            echo "# Local-only additions"
            cat "$LOCAL_GIT_EXCLUDES"
        } >> "$dst" || return 1
    fi
    git config --global core.excludesFile "$dst" || return 1

    mkdir -p "$LOCAL_GIT_HOOKS_DIR" || return 1
    git config --global core.hooksPath "$LOCAL_GIT_HOOKS_DIR" || return 1
}

# ── Homebrew ────────────────────────────────────────────

ensure_brew() {
    if ! command -v brew &>/dev/null; then
        echo "Installing Homebrew..."
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
        <string>$SCRIPTS_DIR/mm_auto.sh</string>
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
    /bin/launchctl bootout "gui/$(id -u)/$LEGACY_LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
    rm -f "$LEGACY_LAUNCH_AGENT_PATH" 2>/dev/null || true

    /bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH" || return 1

    if /bin/launchctl print "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

sync_scripts_to_icloud() {
    if [[ ! -d "$ICLOUD_SCRIPTS_ROOT" ]]; then
        log_warn "iCloud Scripts folder not found, skipping sync"
        return 0
    fi

    mkdir -p "$ICLOUD_BOOTSTRAP_DIR"

    if rsync -av --delete "$SCRIPTS_DIR/" "$ICLOUD_BOOTSTRAP_DIR/" >/dev/null 2>&1; then
        log_ok "iCloud bootstrap copy updated"
    else
        log_warn "Failed to update iCloud bootstrap copy"
        return 1
    fi
}
