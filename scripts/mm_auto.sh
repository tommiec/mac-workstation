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
trap 'record_script_result "mm_auto.sh" "$?" "$RUN_LOG"' EXIT

notify_user "Mac Manager started" "Automated maintenance started."

echo "── ⚡ Auto maintenance ──"

run_quiet_step() {
    local msg="$1"; shift
    local tmp_out

    tmp_out="$(mktemp "${TMPDIR:-/tmp}/mm_auto_step.XXXXXX")" || {
        log_warn "$msg failed (could not create temp log)"
        return 1
    }

    if "$@" > "$tmp_out" 2>&1; then
        cat "$tmp_out" >> "$RUN_LOG"
        rm -f "$tmp_out"
        log_ok "$msg"
    else
        cat "$tmp_out" >> "$RUN_LOG"
        log_warn "$msg failed"
        echo "      Last output:"
        tail -n 12 "$tmp_out" | sed 's/^/      /'
        rm -f "$tmp_out"
        return 1
    fi
}

# ── Self-update ──────────────────────

echo
echo "── 🔄 Scripts ────────────────────────────────────"

if [[ -d "$REPO_ROOT/.git" ]] && command -v git &>/dev/null; then
    BEFORE_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
    if GIT_TERMINAL_PROMPT=0 git -C "$REPO_ROOT" pull --ff-only --quiet >> "$RUN_LOG" 2>&1; then
        AFTER_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "$BEFORE_SHA" && "$BEFORE_SHA" == "$AFTER_SHA" ]]; then
            log_ok "Scripts already up to date"
        else
            log_ok "Scripts updated from GitHub"
        fi
    else
        log_warn "Script update failed (offline or diverged); continuing with local version"
    fi
fi

# ── Brew ─────────────────────────────
# brew is checked through command -v, not ensure_brew:
# in a scheduled night job, we do not want to start an interactive Homebrew install.

echo
echo "── 🍺 Homebrew ───────────────────────────────────"

if command -v brew &>/dev/null; then
    run_quiet_step "brew update" brew update

    OUTDATED_FORMULAS="$(brew outdated --formula --quiet 2>/dev/null || true)"
    OUTDATED_COUNT="$(echo "$OUTDATED_FORMULAS" | awk 'NF { count++ } END { print count + 0 }')"
    if [[ "$OUTDATED_COUNT" -eq 0 ]]; then
        log_ok "No outdated Homebrew formulas"
    else
        echo "   ℹ️  $OUTDATED_COUNT Homebrew formula(s) to upgrade"
        while IFS= read -r formula; do
            [[ -n "$formula" ]] && echo "      - $formula"
        done <<< "$OUTDATED_FORMULAS"
        run_quiet_step "brew upgrade ($OUTDATED_COUNT formula(s))" brew upgrade --formula
    fi

    run_quiet_step "brew cleanup" brew cleanup --prune=30
    run_quiet_step "brew autoremove" brew autoremove
else
    log_warn "brew unavailable — skipping brew steps"
fi

# Detect upgrades by observed state, independent of who ran `brew upgrade` or
# whether another formula made a bulk upgrade return a failure. A deliberately
# stopped service stays stopped because kickstart is only considered when the
# Mac Manager LaunchAgent is loaded.
if command -v ollama >/dev/null 2>&1 \
    && /bin/launchctl print "gui/$(id -u)/$OLLAMA_SERVICE_LABEL" >/dev/null 2>&1; then
    OLLAMA_CLI_VERSION="$(ollama_cli_version)"
    OLLAMA_SERVER_VERSION="$(ollama_server_version)"
    if [[ -n "$OLLAMA_CLI_VERSION" && -n "$OLLAMA_SERVER_VERSION" \
        && "$OLLAMA_CLI_VERSION" != "$OLLAMA_SERVER_VERSION" ]]; then
        if restart_ollama_service && wait_for_ollama; then
            log_ok "Ollama restarted after version change ($OLLAMA_SERVER_VERSION → $OLLAMA_CLI_VERSION)"
        else
            log_warn "Ollama restart after version change failed"
        fi
    fi
fi

# ── macOS updates ────────────────────
# Detect and report only; installation happens through 'mm maintain'.
# softwareupdate --list writes to stderr; 2>&1 captures it.

echo
echo "── 🍎 macOS ──────────────────────────────────────"

UPDATES="$(/usr/sbin/softwareupdate --list 2>&1 || true)"
COUNT="$(count_macos_updates "$UPDATES")"

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

echo
echo "── 🧹 Cache cleanup ──────────────────────────────"

DELETED=$(
    /usr/bin/find "$HOME/Library/Caches" \
        -type f -mtime +7 \
        -print -delete 2>/dev/null \
    | /usr/bin/wc -l \
    | /usr/bin/tr -d ' '
)
log_ok "$DELETED old cache file(s) deleted"

OLD_LOG_COUNT=$(
    /usr/bin/find "$LOG_DIR" \
        -type f \( -name 'auto_*.log' -o -name 'maintain_*.log' \) \
        -mtime "+$LOG_RETENTION_DAYS" \
        -print -delete 2>/dev/null \
    | /usr/bin/wc -l \
    | /usr/bin/tr -d ' '
)

TRUNCATED_LOG_COUNT=0
for service_log in "$LOG_DIR/ollama.out" "$LOG_DIR/ollama.err"; do
    if [[ -f "$service_log" ]] \
        && [[ "$(/usr/bin/stat -f '%z' "$service_log" 2>/dev/null || echo 0)" -gt "$OLLAMA_LOG_MAX_BYTES" ]]; then
        : > "$service_log"
        TRUNCATED_LOG_COUNT=$((TRUNCATED_LOG_COUNT + 1))
    fi
done
log_ok "$OLD_LOG_COUNT manager log(s) older than $LOG_RETENTION_DAYS days deleted; $TRUNCATED_LOG_COUNT oversized Ollama log(s) truncated"

notify_user "Mac Manager completed" "Maintenance finished."

summary_print
