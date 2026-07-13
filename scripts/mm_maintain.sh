#!/bin/bash
# =========================================================
# mm_maintain.sh
# Run maintenance now: Homebrew, DNS flush, macOS updates, optional SSH backup
#
# Usage (after installation):
#   mm maintain
#   or
#   bash ~/Repositories/dev/mac-workstation/scripts/mm_maintain.sh
#
# What this script does:
#   - Runs brew doctor
#   - Optionally upgrades outdated Homebrew casks
#   - Flushes the DNS cache
#   - Detects and optionally installs macOS updates
#   - Optionally backs up ~/.ssh to the encrypted iCloud vault
#   - Optionally backs up GPG keys/trust to the encrypted iCloud vault
#   - Optionally clears QuickTime recent documents history
#
# Some steps request sudo only when needed.
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mm_common.sh"

RUN_LOG="$LOG_DIR/maintain_$(date '+%Y-%m-%d_%H-%M-%S').log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$RUN_LOG") 2>&1
trap 'record_script_result "mm_maintain.sh" "$?" "$RUN_LOG"' EXIT

notify_user "Mac Manager started" "Maintenance run started."

echo "── 🔍 Mac Manager maintenance ──"
echo
echo "Privileged steps ask for your macOS password only when needed."
echo "Passwords are handled by sudo and are never logged."

echo
echo "── 🍺 Homebrew ───────────────────────────────────"

# ── Brew doctor ──────────────────────
# brew doctor exits with 0 on a healthy system, otherwise 1.
# We show the full output and log based on the exit code,
# not by grepping the output (more robust across Homebrew text changes).

BREW_DOCTOR_STATUS=0
BREW_DOCTOR_OUT="$(brew doctor 2>&1)" || BREW_DOCTOR_STATUS=$?
echo "$BREW_DOCTOR_OUT" >> "$RUN_LOG"

if [[ "$BREW_DOCTOR_STATUS" -eq 0 ]]; then
    log_ok "brew doctor OK"
else
    log_warn "brew doctor reported warnings — details saved to $RUN_LOG"
    echo "$BREW_DOCTOR_OUT" | grep -E '^(Warning:|Error:)' | head -n 5 | sed 's/^/      /' || true
fi

# ── Homebrew cask upgrades ───────────

run_step "brew update" brew update

OUTDATED_CASKS_RAW="$(brew outdated --cask --quiet 2>/dev/null || true)"
OUTDATED_CASK_COUNT="$(printf '%s\n' "$OUTDATED_CASKS_RAW" | awk 'NF { count++ } END { print count + 0 }')"

if [[ "$OUTDATED_CASK_COUNT" -eq 0 ]]; then
    log_ok "No outdated Homebrew casks"
else
    log_warn "$OUTDATED_CASK_COUNT Homebrew cask(s) available for upgrade"
    while IFS= read -r cask; do
        [[ -n "$cask" ]] && echo "      - $cask"
    done <<< "$OUTDATED_CASKS_RAW"

    read -r -p "   Upgrade Homebrew casks? (y/N): " confirm_casks

    if [[ "$confirm_casks" =~ ^[Yy]$ ]]; then
        OUTDATED_CASKS=()
        CASK_UPGRADED=0
        CASK_FAILED=0
        CASK_FAILED_NAMES=""
        while IFS= read -r cask; do
            [[ -n "$cask" ]] && OUTDATED_CASKS+=("$cask")
        done <<< "$OUTDATED_CASKS_RAW"

        for cask in "${OUTDATED_CASKS[@]}"; do
            echo "   Upgrading cask: $cask"
            if brew upgrade --cask "$cask"; then
                CASK_UPGRADED=$((CASK_UPGRADED + 1))
            else
                CASK_FAILED=$((CASK_FAILED + 1))
                CASK_FAILED_NAMES="${CASK_FAILED_NAMES:+$CASK_FAILED_NAMES, }$cask"
            fi
        done

        if [[ "$CASK_FAILED" -eq 0 ]]; then
            log_ok "Homebrew casks upgraded ($CASK_UPGRADED)"
        else
            log_warn "Homebrew casks: $CASK_UPGRADED upgraded, $CASK_FAILED failed ($CASK_FAILED_NAMES)"
        fi
    else
        log_info "Homebrew cask upgrades skipped"
    fi
fi

# ── DNS flush ────────────────────────

echo
echo "── 🌐 DNS ────────────────────────────────────────"
echo "   macOS may ask for your password to flush DNS."

if sudo /bin/sh -c 'dscacheutil -flushcache && killall -HUP mDNSResponder'; then
    log_ok "DNS cache flushed"
else
    log_warn "DNS flush failed"
fi

# ── macOS updates ────────────────────
# grep -c exits with 1 for 0 matches; || true handles that.

echo
echo "── 🍎 macOS updates ──────────────────────────────"

UPDATES="$(/usr/sbin/softwareupdate --list 2>&1 || true)"
echo "$UPDATES" >> "$RUN_LOG"

COUNT=$(echo "$UPDATES" | grep -cE '^[[:space:]]*\*' || true)
COUNT=${COUNT:-0}

if [[ "$COUNT" -eq 0 ]]; then
    log_ok "No macOS updates available"
else
    log_warn "$COUNT macOS update(s) available"
    echo "$UPDATES" | awk '/^[[:space:]]*\*/ { sub(/^[[:space:]]*\*[[:space:]]*/, ""); print "      - " $0 }'

    read -r -p "   Install updates? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "   macOS may ask for your password to install updates."
        INSTALL_OUT="$(sudo /usr/sbin/softwareupdate --install --all 2>&1 || true)"
        echo "$INSTALL_OUT"

        if echo "$INSTALL_OUT" | grep -q "No updates are available"; then
            log_info "No updates available anymore"
        elif echo "$INSTALL_OUT" | grep -qiE "installed|Done|restart"; then
            log_ok "Updates installed"
        else
            log_warn "Update result unclear — check output above"
        fi
    else
        log_info "Updates skipped"
    fi
fi

# ── SSH backup ───────────────────────
echo
echo "── 🔐 SSH backup ─────────────────────────────────"

read -r -p "   Backup ~/.ssh to encrypted iCloud vault? (y/N): " confirm_backup
if [[ "$confirm_backup" =~ ^[Yy]$ ]]; then
    if bash "$SCRIPT_DIR/mm_backup_ssh.sh"; then
        log_ok "SSH backup completed"
    else
        log_warn "SSH backup failed"
    fi
else
    log_info "SSH backup skipped"
fi

# ── GPG backup ───────────────────────
echo
echo "── 🔏 GPG backup ─────────────────────────────────"

read -r -p "   Backup GPG keys and trust to encrypted iCloud vault? (y/N): " confirm_gpg_backup
if [[ "$confirm_gpg_backup" =~ ^[Yy]$ ]]; then
    if bash "$SCRIPT_DIR/mm_backup_gpg.sh"; then
        log_ok "GPG backup completed"
    else
        log_warn "GPG backup failed"
    fi
else
    log_info "GPG backup skipped"
fi

clear_quicktime_history() {
    local recents_dir="$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"
    local quicktime_running=""
    local deleted_files=0
    local deleted_prefs=0
    local failed=0
    local file=""
    local key=""

    quicktime_running="$(osascript -e 'application id "com.apple.QuickTimePlayerX" is running' 2>/dev/null || true)"
    if [[ "$quicktime_running" == "true" ]]; then
        if osascript -e 'tell application id "com.apple.QuickTimePlayerX" to quit' >/dev/null 2>&1; then
            sleep 1
        else
            echo "   Could not quit QuickTime Player before clearing history"
            failed=1
        fi
    fi

    if [[ -d "$recents_dir" ]]; then
        while IFS= read -r -d '' file; do
            if rm -f "$file"; then
                (( deleted_files++ )) || true
            else
                echo "   Could not remove QuickTime recent document file: $file"
                failed=1
            fi
        done < <(find "$recents_dir" -maxdepth 1 -type f -name 'com.apple.quicktimeplayerx.sfl*' -print0 2>/dev/null)
    fi

    for key in NSRecentDocumentRecords MGPlayableDocumentHistory; do
        if defaults read com.apple.QuickTimePlayerX "$key" >/dev/null 2>&1; then
            if defaults delete com.apple.QuickTimePlayerX "$key" >/dev/null 2>&1; then
                (( deleted_prefs++ )) || true
            else
                echo "   Could not delete QuickTime preference key: $key"
                failed=1
            fi
        fi
    done

    if ! launchctl kickstart -k "gui/$(id -u)/com.apple.sharedfilelistd" >/dev/null 2>&1; then
        log_info "sharedfilelistd restart skipped; recents may refresh after logout/login"
    fi

    if [[ "$failed" -ne 0 ]]; then
        log_warn "QuickTime history cleanup incomplete"
        return 1
    fi

    if [[ "$deleted_files" -eq 0 && "$deleted_prefs" -eq 0 ]]; then
        log_ok "QuickTime history already clear"
    else
        log_ok "QuickTime history cleared ($deleted_files file(s), $deleted_prefs preference key(s))"
    fi
}

# ── QuickTime history ────────────────
echo
echo "── 🎬 QuickTime history ──────────────────────────"

read -r -p "   Clear QuickTime recent documents? (y/N): " confirm_qt
if [[ "$confirm_qt" =~ ^[Yy]$ ]]; then
    clear_quicktime_history
else
    log_info "QuickTime history skipped"
fi

notify_user "Mac Manager completed" "Maintenance run finished."

summary_print
