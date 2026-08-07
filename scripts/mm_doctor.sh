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

if echo "$PATH" | tr ':' '\n' | grep -Fxq "$BIN_DIR"; then
    check_ok "PATH contains ~/.local/bin"
else
    check_fail "PATH does not contain ~/.local/bin"
    # shellcheck disable=SC2016
    echo '   Add this to ~/.zshrc: export PATH="$HOME/.local/bin:$PATH"'
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

# ── Repo / scripts ──────────────────────────────────────

if [[ -d "$REPO_ROOT/scripts" ]]; then
    check_ok "Repo scripts folder exists: $REPO_ROOT/scripts"
else
    check_fail "Repo scripts folder missing: $REPO_ROOT/scripts"
fi

for f in mm_common.sh mm_auto.sh mm_maintain.sh mm_install.sh mm_doctor.sh mm_triage.sh mm_backup_ssh.sh mm_backup_gpg.sh; do
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

# ── Git hygiene ─────────────────────────────────────────

echo
echo "── 🧹 Git hygiene ───────────────────────────────"

GLOBAL_EXCLUDES="$(git config --global core.excludesFile 2>/dev/null || true)"
if [[ "$GLOBAL_EXCLUDES" == "$HOME/.config/git/ignore" && -f "$GLOBAL_EXCLUDES" ]]; then
    check_ok "Global git excludes configured: $GLOBAL_EXCLUDES"
    if grep -Fxq "AGENTS.md" "$GLOBAL_EXCLUDES"; then
        check_ok "Global git excludes include AGENTS.md"
    else
        check_fail "Global git excludes do not include AGENTS.md"
    fi
else
    check_fail "Global git excludes not configured as expected"
fi

GLOBAL_HOOKS="$(git config --global core.hooksPath 2>/dev/null || true)"
if [[ "$GLOBAL_HOOKS" == "$LOCAL_GIT_HOOKS_DIR" ]]; then
    check_ok "Global git hooks path configured: $GLOBAL_HOOKS"
else
    check_fail "Global git hooks path not configured as expected"
fi

while IFS= read -r HOOK_SRC; do
    HOOK_NAME="$(basename "$HOOK_SRC")"
    HOOK_DST="$LOCAL_GIT_HOOKS_DIR/$HOOK_NAME"
    if [[ -x "$HOOK_DST" ]]; then
        if cmp -s "$HOOK_SRC" "$HOOK_DST"; then
            check_ok "Managed $HOOK_NAME hook installed and executable"
        else
            check_warn "Installed $HOOK_NAME hook differs from the repository version"
        fi
    else
        check_warn "Managed $HOOK_NAME hook missing or not executable"
    fi
done < <(find "$CONFIGS_DIR/hooks" -maxdepth 1 -type f -print | sort)

if cmp -s "$CONFIGS_DIR/ignore.local" "$LOCAL_GIT_EXCLUDES"; then
    check_ok "Managed local Git excludes installed"
else
    check_warn "Installed local Git excludes differ from the repository version"
fi

# ── Git identity ────────────────────────────────────────
# The profile is the only source of the commit identity and the forge URLs. It
# is machine-local and vault-backed, never stored in this public repo, so the
# checks below verify presence and effect rather than comparing against a
# repository copy.

if [[ -f "$GIT_PROFILE_CONF" ]]; then
    check_ok "Git profile present: $GIT_PROFILE_CONF"

    if [[ "$(git config --global --get user.useConfigOnly)" == "true" ]]; then
        check_ok "user.useConfigOnly is on (git never guesses an identity)"
    else
        check_fail "user.useConfigOnly is not set — git may commit under a guessed address"
    fi

    GLOBAL_IDENT=""
    for KEY in user.name user.email; do
        if [[ -n "$(git config --global --get "$KEY")" ]]; then
            GLOBAL_IDENT="$GLOBAL_IDENT $KEY"
        fi
    done
    if [[ -n "$GLOBAL_IDENT" ]]; then
        check_fail "Global identity set (${GLOBAL_IDENT# }); identity must come per forge"
    else
        check_ok "No global commit identity (correct: identity is per forge)"
    fi

    while IFS= read -r FORGE; do
        [[ -n "$FORGE" ]] || continue
        if [[ -f "${LOCAL_GIT_IDENTITY_PREFIX}-$FORGE" ]]; then
            check_ok "Identity file installed for forge '$FORGE'"
        else
            check_fail "Identity file missing for forge '$FORGE' — run 'mm install'"
        fi
    done < <(git_profile_forges)
else
    check_fail "Git profile missing: $GIT_PROFILE_CONF"
    echo "   Restore it with 'mm restore --git-profile --apply', then run 'mm install'"
fi

# Every repository in the managed workspace must resolve an identity, and it must
# come from a managed identity file: a per-repo override resolves an identity too,
# so checking only for a name and address would pass exactly the state the policy
# forbids. Without a depth limit on purpose: several repos are plain clones nested
# inside another repo's working tree.
GIT_IDENT_TOTAL=0
GIT_IDENT_BAD=0
while IFS=$'\t' read -r REPO_PATH IDENT IDENT_FROM; do
    [[ -n "$REPO_PATH" ]] || continue
    GIT_IDENT_TOTAL=$((GIT_IDENT_TOTAL + 1))
    if [[ "$IDENT" != *"<"*">"* ]]; then
        GIT_IDENT_BAD=$((GIT_IDENT_BAD + 1))
        check_fail "No identity in $REPO_PATH"
    elif [[ "$IDENT_FROM" != "$LOCAL_GIT_IDENTITY_PREFIX"-* ]]; then
        GIT_IDENT_BAD=$((GIT_IDENT_BAD + 1))
        check_fail "$REPO_PATH overrides its identity in ${IDENT_FROM:-<unknown>}"
    fi
done < <(git_workspace_identities)

if [[ "$GIT_IDENT_TOTAL" -eq 0 ]]; then
    check_warn "No repositories found under $WORKSPACE_ROOT/{${WORKSPACE_SCOPES[*]// /,}}"
elif [[ "$GIT_IDENT_BAD" -eq 0 ]]; then
    check_ok "All $GIT_IDENT_TOTAL workspace repositories take their identity from a managed file"
fi

# ── Git repository ──────────────────────────────────────

if [[ -d "$REPO_ROOT/.git" ]]; then
    check_ok "Repo is a git checkout"

    if command -v git >/dev/null 2>&1; then
        check_ok "git found"

        REMOTE_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
        if [[ -z "$REMOTE_URL" ]]; then
            check_warn "Git remote 'origin' is not configured"
        else
            check_ok "Git remote: origin ($REMOTE_URL)"
            # Report only — doctor never changes the checkout. Updating is
            # 'git pull --ff-only' or the weekly auto run.
            if GIT_TERMINAL_PROMPT=0 git -C "$REPO_ROOT" fetch --quiet 2>/dev/null; then
                BEHIND="$(git -C "$REPO_ROOT" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo "")"
                if [[ -z "$BEHIND" ]]; then
                    check_warn "No upstream branch configured; cannot compare with GitHub"
                elif [[ "$BEHIND" -eq 0 ]]; then
                    check_ok "Scripts up to date with GitHub"
                else
                    check_warn "Scripts are $BEHIND commit(s) behind GitHub — run 'git pull --ff-only'"
                fi
            else
                check_warn "Could not reach GitHub to compare versions (offline?)"
            fi
        fi
    else
        check_warn "Repo is a git checkout, but git is not available"
    fi
else
    check_fail "Canonical repository is not a git checkout: $REPO_ROOT"
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

    if grep -Fq "$EXPECTED_REPO" "$LAUNCH_AGENT_PATH"; then
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
        check_warn "$OUTDATED_COUNT outdated Homebrew package(s) — run 'mm maintain'"
    fi

    if [[ -f "$BREWFILE" ]]; then
        MISSING_PACKAGES="$(list_missing_brewfile_packages)"
        if [[ -z "$MISSING_PACKAGES" ]]; then
            check_ok "All Brewfile packages installed"
        else
            check_warn "Brewfile packages not installed — run 'mm install':"
            echo "$MISSING_PACKAGES" | sed 's/^/      /'
        fi

        UNMANAGED="$(list_unmanaged_packages)"
        if [[ -z "$UNMANAGED" ]]; then
            check_ok "No packages installed outside the Brewfile"
        else
            check_warn "Packages installed outside the Brewfile — add them or uninstall:"
            echo "$UNMANAGED" | sed 's/^/      /'
        fi
    else
        check_fail "Brewfile missing: $BREWFILE"
    fi
else
    check_fail "Homebrew not found"
fi

# ── Ollama ──────────────────────────────────────────────

echo
echo "── 🦙 Ollama ─────────────────────────────────────"

if command -v ollama >/dev/null 2>&1; then
    check_ok "Ollama CLI found: $(command -v ollama)"
else
    check_warn "Ollama not installed — skipping checks"
fi

if command -v ollama >/dev/null 2>&1; then
    if [[ -f "$OLLAMA_SERVICE_PATH" ]]; then
        check_ok "Ollama Mac Manager service plist present"
        OLLAMA_EXPECTED_PLIST="$(mktemp "${TMPDIR:-/tmp}/mm-doctor-ollama.XXXXXX" 2>/dev/null || true)"
        if [[ -n "$OLLAMA_EXPECTED_PLIST" ]] \
            && write_ollama_launch_agent "$OLLAMA_EXPECTED_PLIST" \
            && cmp -s "$OLLAMA_EXPECTED_PLIST" "$OLLAMA_SERVICE_PATH"; then
            check_ok "Ollama service plist matches all managed settings"
        else
            check_fail "Ollama service plist differs from the managed configuration"
        fi
        [[ -n "$OLLAMA_EXPECTED_PLIST" ]] && rm -f "$OLLAMA_EXPECTED_PLIST"
    else
        check_fail "Ollama Mac Manager service plist missing: $OLLAMA_SERVICE_PATH"
    fi

    if launchctl print "gui/$(id -u)/$OLLAMA_SERVICE_LABEL" >/dev/null 2>&1; then
        check_ok "Ollama Mac Manager service loaded: $OLLAMA_SERVICE_LABEL"
    else
        check_fail "Ollama Mac Manager service not loaded: $OLLAMA_SERVICE_LABEL"
    fi

    if launchctl print "gui/$(id -u)/$OLLAMA_HOMEBREW_SERVICE_LABEL" >/dev/null 2>&1; then
        check_fail "Conflicting Ollama Homebrew service is loaded: $OLLAMA_HOMEBREW_SERVICE_LABEL"
    else
        check_ok "No conflicting Ollama Homebrew service loaded"
    fi

    if /usr/sbin/lsof -nP -iTCP:11434 -sTCP:LISTEN 2>/dev/null | grep -q 'TCP \*:11434 (LISTEN)'; then
        check_ok "Ollama LAN binding active on *:11434"
    else
        check_fail "Ollama is not actively listening on the LAN at *:11434"
    fi

    OLLAMA_SERVER_VERSION="$(ollama_server_version)"
    if [[ -n "$OLLAMA_SERVER_VERSION" ]]; then
        check_ok "Ollama API responding locally (server $OLLAMA_SERVER_VERSION)"

        OLLAMA_CLI_VERSION="$(ollama_cli_version)"
        if [[ -z "$OLLAMA_CLI_VERSION" ]]; then
            check_warn "Could not determine the installed Ollama CLI version"
        elif [[ "$OLLAMA_CLI_VERSION" == "$OLLAMA_SERVER_VERSION" ]]; then
            check_ok "Ollama CLI and server versions match: $OLLAMA_CLI_VERSION"
        else
            check_warn "Ollama server $OLLAMA_SERVER_VERSION differs from CLI $OLLAMA_CLI_VERSION — restart required"
        fi

        OLLAMA_MISSING_MODELS=0
        for model in "${OLLAMA_MODELS[@]}"; do
            if ollama show "$model" >/dev/null 2>&1; then
                check_ok "Ollama model present: $model"
            else
                check_warn "Ollama model missing: $model — run 'mm install'"
                OLLAMA_MISSING_MODELS=$((OLLAMA_MISSING_MODELS + 1))
            fi
        done

        if [[ "$OLLAMA_MISSING_MODELS" -eq 0 ]]; then
            check_ok "All managed Ollama models installed"
        fi
    else
        check_fail "Ollama API not responding at $OLLAMA_LOCAL_API"
    fi
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
            line_no="${line%%:*}"
            assignment="${line#*:}"
            secret_name="$(echo "$assignment" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/[[:space:]]*=.*$//')"
            echo "      $(basename "$dotfile"):$line_no  $secret_name=<hidden>"
        done <<< "$MATCHES"
        PLAIN_SECRET_FOUND=1
    fi
done

if [[ "$PLAIN_SECRET_FOUND" -eq 0 ]]; then
    check_ok "No plain-text secrets detected in dotfiles"
fi

# GPG secret-key exports are useful for restore, but should not linger in
# ordinary folders after they have been moved into the encrypted vault.
for exported_key in \
    "$HOME/secret-keys.asc" \
    "$HOME/Desktop/secret-keys.asc" \
    "$HOME/Downloads/secret-keys.asc"; do
    if [[ -f "$exported_key" ]] && grep -q "BEGIN PGP PRIVATE KEY BLOCK" "$exported_key" 2>/dev/null; then
        check_warn "Plain-text GPG secret key export found: $exported_key; move it to the encrypted vault and delete the local copy"
    fi
done

# SSH private keys — existence and hygiene
if [[ -d "$HOME/.ssh" ]]; then
    check_ok "$HOME/.ssh folder exists"

    SSH_DIR_PERMS="$(stat -f "%A" "$HOME/.ssh" 2>/dev/null || true)"
    if [[ -n "$SSH_DIR_PERMS" && "$SSH_DIR_PERMS" != "700" ]]; then
        check_warn "$HOME/.ssh has permissions $SSH_DIR_PERMS; recommended: chmod 700 \"$HOME/.ssh\""
    fi

    SSH_KEY_COUNT=0
    SSH_WARN=0

    while IFS= read -r keyfile; do
        header="$(head -1 "$keyfile" 2>/dev/null || true)"
        echo "$header" | grep -qE '^-----BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY-----' || continue

        KEYGEN_OUT="$(ssh-keygen -l -f "$keyfile" 2>/dev/null || true)"
        [[ -z "$KEYGEN_OUT" ]] && continue

        if [[ "$SSH_KEY_COUNT" -eq 0 ]]; then
            echo
            echo "   🗝  SSH private keys:"
            echo
        fi

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
            FLAGS="${FLAGS}⚠ DSA (insecure)"
            SSH_WARN=$((SSH_WARN + 1))
        elif [[ "$KEY_TYPE_UPPER" == "RSA" && -n "$BITS" && "$BITS" -lt 3072 ]]; then
            [[ -n "$FLAGS" ]] && FLAGS="$FLAGS  "
            FLAGS="${FLAGS}⚠ RSA < 3072b"
            SSH_WARN=$((SSH_WARN + 1))
        fi

        printf "   %-24s %-7s %4sb  %-47s  modified: %s  perms: %s%s\n" \
            "$keyname" "$KEY_TYPE" "$BITS" "$FINGERPRINT" "$MODIFIED" "$PERMS" \
            "${FLAGS:+  $FLAGS}"

    done < <(find "$HOME/.ssh" -maxdepth 1 -type f \
        ! -name "*.pub" ! -name "known_hosts" ! -name "known_hosts.old" \
        ! -name "config" ! -name "authorized_keys" 2>/dev/null | sort)

    echo
    if [[ "$SSH_KEY_COUNT" -eq 0 ]]; then
        echo "   🗝  SSH private keys:"
        echo "      none found"
        check_ok "No SSH private keys found in ~/.ssh"
    elif [[ "$SSH_WARN" -eq 0 ]]; then
        check_ok "$SSH_KEY_COUNT SSH private key(s) — no hygiene issues"
    else
        check_warn "$SSH_KEY_COUNT SSH private key(s) — $SSH_WARN attention point(s) (see above)"
    fi

    echo
    echo "   🧭 SSH known hosts:"
    echo

    KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
    if [[ -f "$KNOWN_HOSTS_FILE" ]]; then
        KH_MODIFIED="$(stat -f "%Sm" -t "%Y-%m-%d" "$KNOWN_HOSTS_FILE" 2>/dev/null || echo "?")"
        KH_PERMS="$(stat -f "%A" "$KNOWN_HOSTS_FILE" 2>/dev/null || echo "?")"
        KH_HOSTS="$(awk 'NF && $1 !~ /^#/ && $1 !~ /^\|1\|/ && !seen[$1]++ { count++ } END { print count + 0 }' "$KNOWN_HOSTS_FILE" 2>/dev/null)"
        KH_HASHED="$(awk 'NF && $1 ~ /^\|1\|/ && !seen[$0]++ { count++ } END { print count + 0 }' "$KNOWN_HOSTS_FILE" 2>/dev/null)"

        printf "   known_hosts              visible: %s  hashed: %s  modified: %s  perms: %s\n" \
            "$KH_HOSTS" "$KH_HASHED" "$KH_MODIFIED" "$KH_PERMS"

        KH_SAMPLE="$(awk 'NF && $1 !~ /^#/ && $1 !~ /^\|1\|/ && !seen[$1]++ { print $1; shown++ } shown == 6 { exit }' \
            "$KNOWN_HOSTS_FILE" 2>/dev/null)"
        if [[ -n "$KH_SAMPLE" ]]; then
            echo "      sample:"
            while IFS= read -r host; do
                echo "        - $host"
            done <<< "$KH_SAMPLE"
        elif [[ "$KH_HASHED" -gt 0 ]]; then
            echo "      sample: hosts are hashed"
        fi
    else
        check_warn "No ~/.ssh/known_hosts found"
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
for script in mm_auto.sh mm_maintain.sh mm_install.sh mm_doctor.sh mm_triage.sh mm_backup_ssh.sh mm_backup_gpg.sh; do
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
