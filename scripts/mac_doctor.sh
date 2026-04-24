#!/bin/bash
# =========================================================
# mac_doctor.sh
# Checks the health of the mac-maintenance setup
# =========================================================

set -o pipefail
set -u

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/mac_common.sh"

REPO_ROOT="$HOME/Repositories/mac-maintenance"
SCRIPTS_ROOT="$HOME/Scripts"
SYMLINK_PATH="$SCRIPTS_ROOT/mac-maintenance"
BIN_DIR="$SCRIPTS_ROOT/bin"
MM_PATH="$BIN_DIR/mm"

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

check_ok() {
    echo "✅ $1"
    OK_COUNT=$((OK_COUNT + 1))
}

check_warn() {
    echo "⚠️  $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

check_fail() {
    echo "❌ $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "── 🩺 mm doctor ──"
echo

# ── PATH ────────────────────────────────────────────────

if echo "$PATH" | tr ':' '\n' | grep -Fxq "$HOME/Scripts/bin"; then
    check_ok "PATH contains ~/Scripts/bin"
else
    check_fail "PATH does not contain ~/Scripts/bin"
    echo '   Add this to ~/.zshrc: export PATH="$HOME/Scripts/bin:$PATH"'
fi

if command -v mm >/dev/null 2>&1; then
    MM_FOUND="$(command -v mm)"
    if [[ "$MM_FOUND" == "$MM_PATH" ]]; then
        check_ok "mm found at the expected location: $MM_FOUND"
    else
        check_warn "mm found at an unexpected location: $MM_FOUND"
    fi
else
    check_fail "mm not found in PATH"
fi

# ── Symlink ─────────────────────────────────────────────

if [[ -L "$SYMLINK_PATH" ]]; then
    TARGET="$(readlink "$SYMLINK_PATH")"
    if [[ "$TARGET" == "$REPO_ROOT" ]]; then
        check_ok "Symlink correct: $SYMLINK_PATH -> $TARGET"
    else
        check_fail "Symlink points to the wrong target: $SYMLINK_PATH -> $TARGET"
    fi
elif [[ -e "$SYMLINK_PATH" ]]; then
    check_fail "$SYMLINK_PATH exists, but is not a symlink"
else
    check_fail "Symlink missing: $SYMLINK_PATH"
fi

# ── Repo / scripts ──────────────────────────────────────

if [[ -d "$REPO_ROOT/scripts" ]]; then
    check_ok "Repo scripts folder exists: $REPO_ROOT/scripts"
else
    check_fail "Repo scripts folder missing: $REPO_ROOT/scripts"
fi

for f in mac_common.sh mac_auto.sh mac_manual.sh mac_install.sh mac_doctor.sh mac_triage.sh; do
    FILE_PATH="$REPO_ROOT/scripts/$f"
    if [[ -f "$FILE_PATH" ]]; then
        check_ok "$f present"
        if [[ -x "$FILE_PATH" ]]; then
            check_ok "$f is executable"
        else
            check_warn "$f is not executable"
        fi
    else
        check_fail "$f missing"
    fi
done

if [[ -f "$MM_PATH" ]]; then
    check_ok "Wrapper present: $MM_PATH"
    if [[ -x "$MM_PATH" ]]; then
        check_ok "Wrapper is executable"
    else
        check_fail "Wrapper is not executable"
    fi
else
    check_fail "Wrapper missing: $MM_PATH"
fi

# ── LaunchAgent ─────────────────────────────────────────

if [[ -f "$LAUNCH_AGENT_PATH" ]]; then
    check_ok "LaunchAgent plist present"
else
    check_fail "LaunchAgent plist missing: $LAUNCH_AGENT_PATH"
fi

if launchctl print "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1; then
    check_ok "LaunchAgent loaded: $LAUNCH_AGENT_LABEL"
else
    check_warn "LaunchAgent not loaded: $LAUNCH_AGENT_LABEL"
fi

if [[ -f "$LAUNCH_AGENT_PATH" ]]; then
    EXPECTED_REPO="$REPO_ROOT/scripts/mac_auto.sh"
    EXPECTED_SYMLINK="$SYMLINK_PATH/scripts/mac_auto.sh"

    if grep -Fq "$EXPECTED_REPO" "$LAUNCH_AGENT_PATH" || grep -Fq "$EXPECTED_SYMLINK" "$LAUNCH_AGENT_PATH"; then
        check_ok "LaunchAgent points to the expected mac_auto.sh"
    else
        check_fail "LaunchAgent does not point to the expected mac_auto.sh"
    fi
fi

# ── Homebrew ────────────────────────────────────────────

if command -v brew >/dev/null 2>&1; then
    BREW_PATH="$(command -v brew)"
    check_ok "Homebrew found: $BREW_PATH"

    if brew --version >/dev/null 2>&1; then
        check_ok "Homebrew works"
    else
        check_fail "Homebrew command fails"
    fi

    OUTDATED_COUNT="$(brew outdated | wc -l | tr -d ' ')"
    if [[ "${OUTDATED_COUNT:-0}" -eq 0 ]]; then
        check_ok "No outdated Homebrew packages"
    else
        check_warn "$OUTDATED_COUNT outdated Homebrew package(s)"
    fi
else
    check_fail "Homebrew not found"
fi

# ── Logs ────────────────────────────────────────────────

if [[ -d "$LOG_DIR" ]]; then
    check_ok "Log folder exists: $LOG_DIR"
else
    check_warn "Log folder missing: $LOG_DIR"
fi

TEST_LOG="$LOG_DIR/.doctor-write-test"
mkdir -p "$LOG_DIR" 2>/dev/null || true
if touch "$TEST_LOG" 2>/dev/null; then
    rm -f "$TEST_LOG"
    check_ok "Log folder is writable"
else
    check_fail "Log folder is not writable"
fi

# ── Network ─────────────────────────────────────────────

if ping -c 1 -W 1000 1.1.1.1 >/dev/null 2>&1; then
    check_ok "Network connection looks OK"
else
    check_warn "Network test to 1.1.1.1 failed"
fi

# ── Summary ─────────────────────────────────────────────

echo
echo "── 📊 Doctor summary ──────────────────────────────"
echo "✅ OK:            $OK_COUNT"
echo "⚠️  Warnings:      $WARN_COUNT"
echo "❌ Problems:      $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
