#!/bin/bash
# =========================================================
# mm_auto.sh
# Weekly automated maintenance (launchd)
#
# Do not run directly — runs automatically through
# launchd (registered by mm_install.sh).
# Schedule: every Saturday at 02:00
#
# What this script does:
#   - Pulls the latest scripts from GitHub (git checkout only)
#   - Updates and cleans up Homebrew formulas
#   - Detects macOS updates and reports them through a notification
#   - Deletes old cache files (>7 days)
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mm_common.sh"

mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/auto_$(date '+%Y-%m-%d_%H-%M-%S').log"
exec > >(tee -a "$RUN_LOG") 2>&1
trap 'status=$?; record_script_result "mm_auto.sh" "$status" "$RUN_LOG"' EXIT

notify_user "Mac Manager started" "Automated maintenance started."

echo "── ⚡ Auto maintenance ──"

# ── Self-update ──────────────────────

if [[ -d "$REPO_ROOT/.git" ]] && command -v git &>/dev/null; then
    if GIT_TERMINAL_PROMPT=0 git -C "$REPO_ROOT" pull --ff-only --quiet 2>/dev/null; then
        log_ok "Scripts updated from GitHub"
    else
        log_warn "Script update failed (offline or diverged); continuing with local version"
    fi
fi

# ── Brew ─────────────────────────────
# brew is checked through command -v, not ensure_brew:
# in a scheduled night job, we do not want to start an interactive Homebrew install.

if command -v brew &>/dev/null; then
    run_step "brew update"     brew update
    run_step "brew upgrade"    brew upgrade --formula
    run_step "brew cleanup"    brew cleanup --prune=30
    run_step "brew autoremove" brew autoremove
else
    log_warn "brew unavailable — skipping brew steps"
fi

# ── macOS updates ────────────────────
# Detect and report only; installation happens through 'mm maintain'.
# softwareupdate --list writes to stderr; 2>&1 captures it.
# grep -c exits with 1 for 0 matches; || true handles that.

UPDATES="$(/usr/sbin/softwareupdate --list 2>&1 || true)"
COUNT=$(echo "$UPDATES" | grep -cE '^[[:space:]]*\*' || true)
COUNT=${COUNT:-0}

if [[ "$COUNT" -eq 0 ]]; then
    log_ok "No macOS updates available"
else
    log_warn "$COUNT macOS update(s) available"
    notify_user "macOS updates available" "Use 'mm maintain' to install them."
fi

# ── Cache cleanup ────────────────────
# Deletes files older than 7 days from ~/Library/Caches.
# System folders actively used by launchd services
# (for example com.apple.bird for iCloud) are intentionally not excluded:
# files older than 7 days are rarely in use there at 02:00.
# Adjust the -mtime threshold if this causes issues.

DELETED=$(
    /usr/bin/find "$HOME/Library/Caches" \
        -type f -mtime +7 \
        -print -delete 2>/dev/null \
    | /usr/bin/wc -l \
    | /usr/bin/tr -d ' '
)
log_ok "$DELETED old cache file(s) deleted"

notify_user "Mac Manager completed" "Maintenance finished."

summary_print
