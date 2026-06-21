#!/bin/bash
# =========================================================
# mm_doctor.sh
# Checks the health of the mac-workstation setup
# =========================================================

set -o pipefail
set -u

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/mm_common.sh"
trap 'record_script_result "mm_doctor.sh" "$?"' EXIT

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
    # shellcheck disable=SC2016
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

for f in mm_common.sh mm_auto.sh mm_maintain.sh mm_install.sh mm_doctor.sh mm_triage.sh; do
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

# ── GitHub version ──────────────────────────────────────

if [[ -d "$REPO_ROOT/.git" ]]; then
    check_ok "Repo is a git checkout"

    if command -v git >/dev/null 2>&1; then
        check_ok "git found"

        REMOTE_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
        if [[ -z "$REMOTE_URL" ]]; then
            check_warn "Git remote 'origin' is not configured"
        else
            check_ok "Git remote: origin ($REMOTE_URL)"
            PULL_OUT="$(GIT_TERMINAL_PROMPT=0 git -C "$REPO_ROOT" pull --ff-only 2>&1 || true)"
            if echo "$PULL_OUT" | grep -q "Already up to date"; then
                check_ok "Scripts already up to date"
            elif echo "$PULL_OUT" | grep -qE "Fast-forward|Updating"; then
                check_ok "Scripts updated from GitHub"
            else
                check_warn "Could not update from GitHub (offline or diverged)"
            fi
        fi
    else
        check_warn "Repo is a git checkout, but git is not available"
    fi
else
    check_ok "Non-git bootstrap copy detected"

    if command -v curl >/dev/null 2>&1; then
        GITHUB_RAW_BASE="https://raw.githubusercontent.com/tommiec/mac-workstation/main/scripts"
        GITHUB_FETCH_FAILED=0
        GITHUB_MISMATCH_COUNT=0

        if ! TMP_GITHUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mm_doctor_github.XXXXXX")"; then
            check_warn "Could not create temp folder for GitHub version check"
            TMP_GITHUB_DIR=""
            GITHUB_FETCH_FAILED=1
        fi

        if [[ "$GITHUB_FETCH_FAILED" -eq 0 ]]; then
            for f in mm_common.sh mm_auto.sh mm_maintain.sh mm_install.sh mm_doctor.sh mm_triage.sh; do
                LOCAL_FILE="$REPO_ROOT/scripts/$f"
                REMOTE_FILE="$TMP_GITHUB_DIR/$f"

                if ! curl -fsSL "$GITHUB_RAW_BASE/$f" -o "$REMOTE_FILE"; then
                    GITHUB_FETCH_FAILED=1
                    break
                fi

                if ! cmp -s "$LOCAL_FILE" "$REMOTE_FILE"; then
                    GITHUB_MISMATCH_COUNT=$((GITHUB_MISMATCH_COUNT + 1))
                fi
            done
        fi

        if [[ -n "$TMP_GITHUB_DIR" ]]; then
            rm -rf "$TMP_GITHUB_DIR"
        fi

        if [[ "$GITHUB_FETCH_FAILED" -eq 1 ]]; then
            check_warn "Could not compare bootstrap copy with GitHub"
        elif [[ "$GITHUB_MISMATCH_COUNT" -eq 0 ]]; then
            check_ok "Installed scripts match GitHub main"
        else
            check_warn "$GITHUB_MISMATCH_COUNT installed script(s) differ from GitHub main"
        fi
    else
        check_warn "curl not found; GitHub version check skipped"
    fi
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
    EXPECTED_REPO="$REPO_ROOT/scripts/mm_auto.sh"
    EXPECTED_SYMLINK="$SYMLINK_PATH/scripts/mm_auto.sh"

    if grep -Fq "$EXPECTED_REPO" "$LAUNCH_AGENT_PATH" || grep -Fq "$EXPECTED_SYMLINK" "$LAUNCH_AGENT_PATH"; then
        check_ok "LaunchAgent points to the expected mm_auto.sh"
    else
        check_fail "LaunchAgent does not point to the expected mm_auto.sh"
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

# ── Secrets & SSH ───────────────────────────────────────
# Goal: nothing sensitive should live as plain text in dotfiles.
# API keys should come from a password manager, Keychain helper, or another
# command substitution instead of being written directly in shell files.

echo
echo "── 🔑 Secrets & SSH ──────────────────────────────"

DOTFILES_TO_SCAN=(
    "$HOME/.zshrc"
    "$HOME/.zprofile"
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.profile"
)
PLAIN_SECRET_FOUND=0

# Assignments with secret-like names where the value looks literal.
# Dynamic values via $(), $VAR, `cmd`, or empty quotes are intentionally skipped.
SECRET_NAME_RE='^[[:space:]]*(export[[:space:]]+)?((API_?KEY|ACCESS_KEY|TOKEN|SECRET|PASSWORD|PRIVATE_?KEY)[A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*_(API_?KEY|ACCESS_KEY|TOKEN|SECRET|PASSWORD|PRIVATE_?KEY)[A-Za-z0-9_]*)[[:space:]]*='
DYNAMIC_VALUE_RE='=[[:space:]]*([$`]|"[$`]|'"'"'[$`]|""|'\'''\''|$)'

for dotfile in "${DOTFILES_TO_SCAN[@]}"; do
    [[ -f "$dotfile" ]] || continue

    MATCHES="$(grep -nE "$SECRET_NAME_RE" "$dotfile" 2>/dev/null \
        | grep -vE "$DYNAMIC_VALUE_RE" || true)"

    if [[ -n "$MATCHES" ]]; then
        check_warn "Possible plain-text secret in $(basename "$dotfile"); move it to Keychain or your password manager:"
        while IFS= read -r line; do
            # Mask values so secrets never appear in doctor output or logs.
            echo "      ${line%%=*}=<hidden>"
        done <<< "$MATCHES"
        PLAIN_SECRET_FOUND=1
    fi
done

if [[ "$PLAIN_SECRET_FOUND" -eq 0 ]]; then
    check_ok "No plain-text secrets detected in dotfiles"
fi

# SSH private keys — existence and hygiene
if [[ -d "$HOME/.ssh" ]]; then
    check_ok "$HOME/.ssh folder exists"

    SSH_DIR_PERMS="$(stat -f "%A" "$HOME/.ssh" 2>/dev/null || true)"
    if [[ -n "$SSH_DIR_PERMS" && "$SSH_DIR_PERMS" != "700" ]]; then
        check_warn "$HOME/.ssh has permissions $SSH_DIR_PERMS; recommended: chmod 700 \"$HOME/.ssh\""
    fi

    echo
    echo "   🗝  SSH private keys:"
    echo

    SSH_KEY_COUNT=0
    SSH_WARN=0

    while IFS= read -r keyfile; do
        header="$(head -1 "$keyfile" 2>/dev/null || true)"
        echo "$header" | grep -qE '^-----BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY-----' || continue

        KEYGEN_OUT="$(ssh-keygen -l -f "$keyfile" 2>/dev/null || true)"
        [[ -z "$KEYGEN_OUT" ]] && continue

        SSH_KEY_COUNT=$((SSH_KEY_COUNT + 1))
        keyname="$(basename "$keyfile")"
        BITS="$(awk '{print $1}' <<< "$KEYGEN_OUT")"
        FINGERPRINT="$(awk '{print $2}' <<< "$KEYGEN_OUT")"
        KEY_TYPE="$(grep -oE '\([A-Z0-9-]+\)$' <<< "$KEYGEN_OUT" | tr -d '()' | tr '[:upper:]' '[:lower:]')"
        MODIFIED="$(stat -f "%Sm" -t "%Y-%m-%d" "$keyfile" 2>/dev/null || echo "?")"
        PERMS="$(stat -f "%A" "$keyfile" 2>/dev/null || true)"

        FLAGS=""
        if [[ "${PERMS: -2}" != "00" ]]; then
            FLAGS="⚠ perms $PERMS (group/other access)"
            SSH_WARN=$((SSH_WARN + 1))
        fi
        KEY_TYPE_UPPER="$(echo "$KEY_TYPE" | tr '[:lower:]' '[:upper:]')"
        if [[ "$KEY_TYPE_UPPER" == "DSA" ]]; then
            [[ -n "$FLAGS" ]] && FLAGS="$FLAGS  "
            FLAGS="${FLAGS}⚠ DSA (onveilig)"
            SSH_WARN=$((SSH_WARN + 1))
        elif [[ "$KEY_TYPE_UPPER" == "RSA" && -n "$BITS" && "$BITS" -lt 3072 ]]; then
            [[ -n "$FLAGS" ]] && FLAGS="$FLAGS  "
            FLAGS="${FLAGS}⚠ RSA < 3072b"
            SSH_WARN=$((SSH_WARN + 1))
        fi

        printf "   %-24s %-7s %4sb  %-47s  gewijzigd: %s  perms: %s%s\n" \
            "$keyname" "$KEY_TYPE" "$BITS" "$FINGERPRINT" "$MODIFIED" "$PERMS" \
            "${FLAGS:+  $FLAGS}"

    done < <(find "$HOME/.ssh" -maxdepth 1 -type f \
        ! -name "*.pub" ! -name "known_hosts" ! -name "known_hosts.old" \
        ! -name "config" ! -name "authorized_keys" 2>/dev/null | sort)

    echo
    if [[ "$SSH_KEY_COUNT" -eq 0 ]]; then
        check_warn "Geen SSH private keys gevonden in ~/.ssh"
    elif [[ "$SSH_WARN" -eq 0 ]]; then
        check_ok "$SSH_KEY_COUNT SSH private key(s) — geen hygiëneproblemen"
    else
        check_warn "$SSH_KEY_COUNT SSH private key(s) — $SSH_WARN aandachtspunt(en) (zie boven)"
    fi
else
    check_warn "$HOME/.ssh folder not found"
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

# ── Last runs ───────────────────────────────────────────

echo
echo "── 🧾 Last script runs ───────────────────────────"
for script in mm_auto.sh mm_maintain.sh mm_install.sh mm_doctor.sh mm_triage.sh; do
    STATUS_FILE="$SCRIPT_STATUS_DIR/$script.status"

    if [[ ! -f "$STATUS_FILE" ]]; then
        check_warn "$script last run: never recorded"
        continue
    fi

    STATUS="$(grep -E '^status=' "$STATUS_FILE" 2>/dev/null | head -n 1 | cut -d= -f2-)"
    EXIT_CODE="$(grep -E '^exit_code=' "$STATUS_FILE" 2>/dev/null | head -n 1 | cut -d= -f2-)"
    FINISHED_AT="$(grep -E '^finished_at=' "$STATUS_FILE" 2>/dev/null | head -n 1 | cut -d= -f2-)"
    LOG_FILE="$(grep -E '^log_file=' "$STATUS_FILE" 2>/dev/null | head -n 1 | cut -d= -f2-)"

    if [[ "$STATUS" == "success" ]]; then
        check_ok "$script last run: $FINISHED_AT (success, exit $EXIT_CODE)"
    else
        check_warn "$script last run: $FINISHED_AT (${STATUS:-unknown}, exit ${EXIT_CODE:-unknown})"
    fi

    if [[ -n "$LOG_FILE" ]]; then
        echo "   Log: $LOG_FILE"
    fi
done

# ── Summary ─────────────────────────────────────────────

echo
echo "── 📊 Doctor summary ──────────────────────────────"
echo "✅ OK:            $OK_COUNT"
echo "⚠️  Warnings:      $WARN_COUNT"
echo "❌ Problems:      $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
