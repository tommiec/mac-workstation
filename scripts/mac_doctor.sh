#!/bin/bash
# =========================================================
# mac_doctor.sh
# Controleert de gezondheid van de mac-maintenance setup
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
    check_ok "PATH bevat ~/Scripts/bin"
else
    check_fail "PATH bevat ~/Scripts/bin niet"
    echo '   Voeg toe in ~/.zshrc: export PATH="$HOME/Scripts/bin:$PATH"'
fi

if command -v mm >/dev/null 2>&1; then
    MM_FOUND="$(command -v mm)"
    if [[ "$MM_FOUND" == "$MM_PATH" ]]; then
        check_ok "mm gevonden op juiste locatie: $MM_FOUND"
    else
        check_warn "mm gevonden op onverwachte locatie: $MM_FOUND"
    fi
else
    check_fail "mm niet gevonden in PATH"
fi

# ── Symlink ─────────────────────────────────────────────

if [[ -L "$SYMLINK_PATH" ]]; then
    TARGET="$(readlink "$SYMLINK_PATH")"
    if [[ "$TARGET" == "$REPO_ROOT" ]]; then
        check_ok "Symlink correct: $SYMLINK_PATH -> $TARGET"
    else
        check_fail "Symlink wijst fout: $SYMLINK_PATH -> $TARGET"
    fi
elif [[ -e "$SYMLINK_PATH" ]]; then
    check_fail "$SYMLINK_PATH bestaat, maar is geen symlink"
else
    check_fail "Symlink ontbreekt: $SYMLINK_PATH"
fi

# ── Repo / scripts ──────────────────────────────────────

if [[ -d "$REPO_ROOT/scripts" ]]; then
    check_ok "Repo scripts-map bestaat: $REPO_ROOT/scripts"
else
    check_fail "Repo scripts-map ontbreekt: $REPO_ROOT/scripts"
fi

for f in mac_common.sh mac_auto.sh mac_manual.sh mac_install.sh mac_doctor.sh; do
    FILE_PATH="$REPO_ROOT/scripts/$f"
    if [[ -f "$FILE_PATH" ]]; then
        check_ok "$f aanwezig"
        if [[ -x "$FILE_PATH" ]]; then
            check_ok "$f is uitvoerbaar"
        else
            check_warn "$f is niet uitvoerbaar"
        fi
    else
        check_fail "$f ontbreekt"
    fi
done

if [[ -f "$MM_PATH" ]]; then
    check_ok "Wrapper aanwezig: $MM_PATH"
    if [[ -x "$MM_PATH" ]]; then
        check_ok "Wrapper is uitvoerbaar"
    else
        check_fail "Wrapper is niet uitvoerbaar"
    fi
else
    check_fail "Wrapper ontbreekt: $MM_PATH"
fi

# ── LaunchAgent ─────────────────────────────────────────

if [[ -f "$LAUNCH_AGENT_PATH" ]]; then
    check_ok "LaunchAgent plist aanwezig"
else
    check_fail "LaunchAgent plist ontbreekt: $LAUNCH_AGENT_PATH"
fi

if launchctl print "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1; then
    check_ok "LaunchAgent geladen: $LAUNCH_AGENT_LABEL"
else
    check_warn "LaunchAgent niet geladen: $LAUNCH_AGENT_LABEL"
fi

if [[ -f "$LAUNCH_AGENT_PATH" ]]; then
    EXPECTED_REPO="$REPO_ROOT/scripts/mac_auto.sh"
    EXPECTED_SYMLINK="$SYMLINK_PATH/scripts/mac_auto.sh"

    if grep -Fq "$EXPECTED_REPO" "$LAUNCH_AGENT_PATH" || grep -Fq "$EXPECTED_SYMLINK" "$LAUNCH_AGENT_PATH"; then
        check_ok "LaunchAgent verwijst naar juiste mac_auto.sh"
    else
        check_fail "LaunchAgent verwijst niet naar verwachte mac_auto.sh"
    fi
fi

# ── Homebrew ────────────────────────────────────────────

if command -v brew >/dev/null 2>&1; then
    BREW_PATH="$(command -v brew)"
    check_ok "Homebrew gevonden: $BREW_PATH"

    if brew --version >/dev/null 2>&1; then
        check_ok "Homebrew werkt"
    else
        check_fail "Homebrew commando faalt"
    fi

    OUTDATED_COUNT="$(brew outdated | wc -l | tr -d ' ')"
    if [[ "${OUTDATED_COUNT:-0}" -eq 0 ]]; then
        check_ok "Geen verouderde Homebrew packages"
    else
        check_warn "$OUTDATED_COUNT verouderde Homebrew package(s)"
    fi
else
    check_fail "Homebrew niet gevonden"
fi

# ── Logs ────────────────────────────────────────────────

if [[ -d "$LOG_DIR" ]]; then
    check_ok "Logmap bestaat: $LOG_DIR"
else
    check_warn "Logmap ontbreekt: $LOG_DIR"
fi

TEST_LOG="$LOG_DIR/.doctor-write-test"
mkdir -p "$LOG_DIR" 2>/dev/null || true
if touch "$TEST_LOG" 2>/dev/null; then
    rm -f "$TEST_LOG"
    check_ok "Logmap is schrijfbaar"
else
    check_fail "Logmap is niet schrijfbaar"
fi

# ── Netwerk ─────────────────────────────────────────────

if ping -c 1 -W 1000 1.1.1.1 >/dev/null 2>&1; then
    check_ok "Netwerkverbinding lijkt OK"
else
    check_warn "Netwerktest naar 1.1.1.1 mislukt"
fi

# ── Samenvatting ────────────────────────────────────────

echo
echo "── 📊 Doctor samenvatting ─────────────────────────"
echo "✅ OK:            $OK_COUNT"
echo "⚠️  Waarschuwingen: $WARN_COUNT"
echo "❌ Problemen:      $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi