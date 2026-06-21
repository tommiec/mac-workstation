#!/bin/bash
# =========================================================
# mm_maintain.sh
# Run maintenance now: Homebrew, DNS flush, macOS updates
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
#
# Requires sudo (requested once on startup).
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mm_common.sh"

RUN_LOG="$LOG_DIR/maintain_$(date '+%Y-%m-%d_%H-%M-%S').log"

echo "── 🔍 Mac Manager maintenance ──"
echo
echo "This command needs administrator permission to flush DNS and install macOS updates."
echo "macOS will ask for your password now; it is handled by sudo and is never logged."
echo

# ── Sudo ─────────────────────────────
# sudo -v asks for the password once and validates the session.
# The keepalive loop refreshes the sudo timestamp every 50 seconds,
# so long-running steps (for example softwareupdate) do not block.

if ! sudo -v; then
    echo
    echo "❌ Administrator authentication failed. Maintenance aborted."
    exit 1
fi

while true; do
    sudo -n true
    sleep 50
    kill -0 "$$" || exit
done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

cleanup() {
    status="$1"
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    record_script_result "mm_maintain.sh" "$status" "$RUN_LOG"
}

trap 'status=$?; cleanup "$status"' EXIT

mkdir -p "$LOG_DIR"
exec > >(tee -a "$RUN_LOG") 2>&1

notify_user "Mac Manager started" "Maintenance run started."

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

if sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder; then
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

notify_user "Mac Manager completed" "Maintenance run finished."

summary_print
