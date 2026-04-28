#!/bin/bash
# =========================================================
# mac_manual.sh
# Manual maintenance and system checks
#
# Usage (after installation):
#   mm manual
#   or
#   bash ~/Scripts/mac-maintenance/scripts/mac_manual.sh
#
# What this script does:
#   - Runs brew doctor
#   - Flushes the DNS cache
#   - Detects and optionally installs macOS updates
#
# Requires sudo (requested once on startup).
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mac_common.sh"

RUN_LOG="$LOG_DIR/manual_$(date '+%Y-%m-%d_%H-%M-%S').log"

# ── Sudo ─────────────────────────────
# sudo -v asks for the password once and validates the session.
# The keepalive loop refreshes the sudo timestamp every 50 seconds,
# so long-running steps (for example softwareupdate) do not block.

if ! sudo -v; then
    echo "Sudo failed — script aborted."
    exit 1
fi

while true; do
    sudo -n true
    sleep 50
    kill -0 "$$" || exit
done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'status=$?; kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; record_script_result "mac_manual.sh" "$status" "$RUN_LOG"' EXIT

mkdir -p "$LOG_DIR"
exec > >(tee -a "$RUN_LOG") 2>&1

notify_user "Mac maintenance started" "Manual maintenance started."

echo "── 🔍 Manual maintenance ──"

# ── Brew doctor ──────────────────────
# brew doctor exits with 0 on a healthy system, otherwise 1.
# We show the full output and log based on the exit code,
# not by grepping the output (more robust across Homebrew text changes).

if brew doctor; then
    log_ok "brew doctor OK"
else
    log_warn "brew doctor reported warnings — see output above"
fi

# ── DNS flush ────────────────────────

if sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder; then
    log_ok "DNS cache flushed"
else
    log_warn "DNS flush failed"
fi

# ── macOS updates ────────────────────
# grep -c exits with 1 for 0 matches; || true handles that.

UPDATES="$(/usr/sbin/softwareupdate --list 2>&1 || true)"
echo "$UPDATES"

COUNT=$(echo "$UPDATES" | grep -cE '^[[:space:]]*\*' || true)
COUNT=${COUNT:-0}

if [[ "$COUNT" -eq 0 ]]; then
    log_ok "No macOS updates available"
else
    log_warn "$COUNT macOS update(s) available"

    read -r -p "   Install updates? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
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

notify_user "Mac maintenance completed" "Manual maintenance finished."

summary_print
