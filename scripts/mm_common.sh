#!/bin/bash
# =========================================================
# mm_common.sh
# Shared configuration, paths and helper functions
#
# Do not run directly — sourced by the other scripts.
#
# Setup model:
#   Source/runtime:  ~/Repositories/dev/mac-workstation  (git repo)
#   CLI entrypoint:  ~/.local/bin/mm
#
# GitHub is the canonical source. iCloud Drive is used only for encrypted
# backups.
# =========================================================

# ── Config ──────────────────────────────────────────────
# SCRIPTS_DIR points to the scripts directory inside the repo; REPO_ROOT is
# derived from it so there is a single source of truth for the repo location.
# All other scripts source this file and inherit these.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPTS_DIR")"
LOG_DIR="$HOME/Library/Logs/mac_manager"
SCRIPT_STATUS_DIR="$LOG_DIR/status"
CONFIGS_DIR="$REPO_ROOT/configs"
BREWFILE="$REPO_ROOT/Brewfile"
LOCAL_GIT_HOOKS_DIR="$HOME/.config/git/hooks"
LOCAL_GIT_EXCLUDES="$HOME/.config/git/ignore.local"
BIN_DIR="$HOME/.local/bin"
MM_PATH="$BIN_DIR/mm"

# Interactive shells usually learn this through brew shellenv. launchd does
# not read shell profiles, so make the standard Homebrew locations available
# to every Mac Manager script as soon as this shared file is sourced.
# ensure_brew reuses this after a fresh Homebrew install.
load_brew_env() {
    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$brew_bin" ]]; then
            eval "$("$brew_bin" shellenv)"
            return 0
        fi
    done
    return 1
}
load_brew_env || true

LAUNCH_AGENT_LABEL="local.mac-manager.auto-maintenance"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"
LEGACY_LAUNCH_AGENT_LABEL="local.mac.auto-maintenance"
LEGACY_LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/${LEGACY_LAUNCH_AGENT_LABEL}.plist"

# launchd: 0=Sunday ... 6=Saturday
AUTO_WEEKDAY=6
AUTO_HOUR=2
AUTO_MINUTE=0

# The managed app and CLI tool list lives in the repo-root Brewfile
# ($BREWFILE) and is installed by mm_install.sh via 'brew bundle'.

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

# Counts the lines that softwareupdate marks as available updates ('* Label').
# grep -c prints 0 (and exits 1) when nothing matches; || true absorbs that.
count_macos_updates() {
    grep -cE '^[[:space:]]*\*' <<< "${1:-}" || true
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
# Additional ignore rules and managed hooks are stored in this repository and
# installed into ~/.config/git.

install_managed_git_config() {
    local excludes_src="$CONFIGS_DIR/ignore.local"
    local hooks_src="$CONFIGS_DIR/hooks"
    local hooks_dst="$LOCAL_GIT_HOOKS_DIR"

    [[ -f "$excludes_src" ]] || return 1
    [[ -d "$hooks_src" ]] || return 1

    mkdir -p "$(dirname "$LOCAL_GIT_EXCLUDES")" "$hooks_dst" || return 1
    cp "$excludes_src" "$LOCAL_GIT_EXCLUDES" || return 1

    while IFS= read -r hook_file; do
        cp "$hook_file" "$hooks_dst/$(basename "$hook_file")" || return 1
        chmod u+x "$hooks_dst/$(basename "$hook_file")" || return 1
    done < <(find "$hooks_src" -maxdepth 1 -type f -print)
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
    install_managed_git_config || return 1

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

# Lists installed formulas/casks that are not declared in the Brewfile
# (dry-run of 'brew bundle cleanup'). Empty output means nothing unmanaged.
# Only the package sections are kept: the dry-run also prints cache-cleanup
# lines and a --force hint, which are not drift.
list_unmanaged_packages() {
    [[ -f "$BREWFILE" ]] || return 0
    brew bundle cleanup --file "$BREWFILE" 2>/dev/null \
        | awk '/^Would uninstall (formulae|casks):/ { grab=1; print; next }
               /^(Would|Run) / { grab=0 }
               grab && NF' || true
}

# Lists apps in /Applications that no installed Homebrew cask accounts for,
# labelled "(App Store)" or "(manual install)". Matching is best-effort:
# app bundles in the Caskroom, .app names in cask metadata, and normalized
# cask tokens (malwarebytes ↔ Malwarebytes.app). Empty output means every
# app is explained.
list_unmanaged_apps() {
    local caskroom known tokens app name norm
    caskroom="$(brew --prefix 2>/dev/null)/Caskroom"
    [[ -d "$caskroom" ]] || return 0

    known="$( { find "$caskroom" -maxdepth 3 -name '*.app' 2>/dev/null;
        grep -rhoE '"[^"]*\.app"' "$caskroom"/*/.metadata 2>/dev/null | tr -d '"'; } \
        | sed 's|.*/||' | sort -u)"
    tokens="$(brew list --cask 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/-app$//' | tr -d -- '-')"

    for app in /Applications/*.app; do
        [[ -e "$app" ]] || continue
        name="$(basename "$app")"
        [[ "$name" == "Safari.app" ]] && continue
        grep -Fxq "$name" <<< "$known" && continue
        norm="$(printf '%s' "${name%.app}" | tr '[:upper:]' '[:lower:]' | tr -d ' .-')"
        grep -Fxq "$norm" <<< "$tokens" && continue
        if [[ -d "$app/Contents/_MASReceipt" ]]; then
            echo "$name (App Store)"
        else
            echo "$name (manual install)"
        fi
    done
}

ensure_brew() {
    if ! command -v brew &>/dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            || return 1
        # Homebrew's installer updates future login shells, but it cannot
        # update this already-running process.
        load_brew_env || return 1
    fi
    command -v brew &>/dev/null
}

# ── Encrypted vault (iCloud sparsebundle) ───────────────
# Shared by the SSH and GPG backup scripts. Usage pattern:
#   ensure_vault    → create the sparsebundle on first use
#   vault_mount     → sets VAULT_MOUNT_POINT; VAULT_MOUNTED_BY_SCRIPT=1 when
#                     this process mounted it (an already-open vault is reused
#                     and left mounted)
#   vault_eject     → call from the EXIT trap; only ejects what we mounted

VAULT_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Secure Vault/Secrets.sparsebundle"
VAULT_NAME="Secrets"
VAULT_SIZE="2g"
VAULT_MOUNT_POINT=""
VAULT_MOUNTED_BY_SCRIPT=0

ensure_vault() {
    mkdir -p "$(dirname "$VAULT_PATH")" || return 1
    if [[ ! -e "$VAULT_PATH" ]]; then
        echo "Creating encrypted sparsebundle..."
        echo "Choose a strong password and store it in your password manager."
        echo
        diskutil image create blank \
            --encrypt \
            --size "$VAULT_SIZE" \
            --volumeName "$VAULT_NAME" \
            --fs APFS \
            "$VAULT_PATH" || return 1
        echo
    fi
}

vault_mount() {
    local attach_out=""

    if [[ -d "/Volumes/$VAULT_NAME" ]]; then
        VAULT_MOUNT_POINT="/Volumes/$VAULT_NAME"
        echo "Using already mounted vault: $VAULT_MOUNT_POINT"
        return 0
    fi

    echo "Mounting vault..."
    attach_out="$(hdiutil attach "$VAULT_PATH" -nobrowse)" || return 1

    # Take the mount point from the attach output instead of assuming
    # /Volumes/$VAULT_NAME: macOS mounts at "$VAULT_NAME 1" on a name clash.
    VAULT_MOUNT_POINT="$(sed -n 's|.*\(/Volumes/.*\)$|\1|p' <<< "$attach_out" | tail -n 1)"
    if [[ -z "$VAULT_MOUNT_POINT" || ! -d "$VAULT_MOUNT_POINT" ]]; then
        VAULT_MOUNT_POINT=""
        return 1
    fi
    VAULT_MOUNTED_BY_SCRIPT=1
}

vault_eject() {
    if [[ "$VAULT_MOUNTED_BY_SCRIPT" -eq 1 && -n "$VAULT_MOUNT_POINT" && -d "$VAULT_MOUNT_POINT" ]]; then
        diskutil eject "$VAULT_MOUNT_POINT" >/dev/null 2>&1 || true
    fi
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
