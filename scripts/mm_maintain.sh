#!/bin/bash
# =========================================================
# mm_maintain.sh
# Run maintenance now: Homebrew, DNS flush, macOS updates, optional SSH backup
#
# Usage (after installation):
#   mm maintain
#   or
#   bash ~/Scripts/mac-workstation/scripts/mm_maintain.sh
#
# What this script does:
#   - Runs brew doctor
#   - Flushes the DNS cache
#   - Detects and optionally installs macOS updates
#   - Optionally backs up ~/.ssh to the encrypted iCloud vault
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

notify_user "Mac Manager completed" "Maintenance run finished."

summary_print
