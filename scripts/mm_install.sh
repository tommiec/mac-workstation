#!/bin/bash
# =========================================================
# mm_install.sh
# Bootstrap setup script — installs apps and configures Mac Manager automation
#
# Usage (once on a new Mac):
#   GitHub:
#     bash ~/Repositories/dev/mac-workstation/scripts/mm_install.sh
#   iCloud Drive:
#     bash ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts/mac-workstation/scripts/mm_install.sh
#
# What this script does:
#   1. Copies the Mac Manager scripts to:
#        ~/Repositories/dev/mac-workstation/scripts
#   2. Creates a symlink:
#        ~/Scripts/mac-workstation -> ~/Repositories/dev/mac-workstation
#   3. Creates a command wrapper:
#        ~/Scripts/bin/mm
#   4. Installs Homebrew if needed
#   5. Installs all apps from MANAGED_CASKS and CLI_TOOLS
#   6. Registers mm_auto.sh as a weekly launchd agent
#        (every Saturday at 02:00)
#
# After installation:
#   mm auto
#   mm maintain
#   mm install
#   mm doctor
# =========================================================

set -o pipefail
set -u

# SRC_DIR = location of this script (for example iCloud Drive on first run)
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_ROOT="$HOME/Repositories/dev/mac-workstation"
TARGET_DIR="$REPO_ROOT/scripts"
SCRIPTS_ROOT="$HOME/Scripts"
SYMLINK_PATH="$SCRIPTS_ROOT/mac-workstation"
LEGACY_SYMLINK_PATH="$SCRIPTS_ROOT/mac-maintenance"
BIN_DIR="$SCRIPTS_ROOT/bin"
MM_PATH="$BIN_DIR/mm"

mkdir -p "$REPO_ROOT"
mkdir -p "$TARGET_DIR"
mkdir -p "$BIN_DIR"

echo "── 🚀 Installation started ──"

# ── Copy scripts to install location ─────────────────────
# Copies are summarized so repeat installs stay readable.
# mm_install.sh intentionally copies itself, so 'mm install'
# always runs the latest installed version.

COPY_OK=true
COPY_IDENTICAL=0
COPY_UPDATED=0
for f in mm_common.sh mm_auto.sh mm_maintain.sh mm_install.sh mm_doctor.sh mm_triage.sh mm_backup_ssh.sh mm_backup_gpg.sh; do
    SRC="$SRC_DIR/$f"
    DST="$TARGET_DIR/$f"

    if cmp -s "$SRC" "$DST" 2>/dev/null; then
        COPY_IDENTICAL=$((COPY_IDENTICAL + 1))
    elif cp "$SRC" "$DST"; then
        COPY_UPDATED=$((COPY_UPDATED + 1))
    else
        echo "   ❌ failed to copy $f"
        COPY_OK=false
    fi
done

if [[ "$COPY_OK" == false ]]; then
    echo "❌ Not all scripts could be copied. Installation aborted."
    exit 1
fi

chmod +x "$TARGET_DIR"/*.sh
if [[ "$COPY_UPDATED" -eq 0 ]]; then
    echo "   ✅ Scripts unchanged ($COPY_IDENTICAL checked)"
else
    echo "   ✅ Scripts updated ($COPY_UPDATED copied, $COPY_IDENTICAL unchanged)"
fi

# ── Symlink to ~/Scripts/mac-workstation ─────────────────

if [[ -L "$LEGACY_SYMLINK_PATH" ]]; then
    rm -f "$LEGACY_SYMLINK_PATH"
fi

ln -sfn "$REPO_ROOT" "$SYMLINK_PATH"

# ── Create mm command wrapper ────────────────────────────

cat > "$MM_PATH" <<'EOF'
#!/bin/zsh

case "$1" in
  auto)
    shift
    "$HOME/Scripts/mac-workstation/scripts/mm_auto.sh" "$@"
    ;;
  maintain)
    shift
    "$HOME/Scripts/mac-workstation/scripts/mm_maintain.sh" "$@"
    ;;
  install)
    shift
    "$HOME/Scripts/mac-workstation/scripts/mm_install.sh" "$@"
    ;;
  doctor)
    shift
    "$HOME/Scripts/mac-workstation/scripts/mm_doctor.sh" "$@"
    ;;
  triage)
    shift
    "$HOME/Scripts/mac-workstation/scripts/mm_triage.sh" "$@"
    ;;
  help|"")
    echo "Usage:"
    echo "  mm auto      # automated maintenance"
    echo "  mm maintain  # run maintenance now (includes SSH/GPG backup prompts)"
    echo "  mm install   # run setup"
    echo "  mm doctor    # check setup health"
    echo "  mm triage    # quick file/malware triage"
    ;;
  *)
    echo "Unknown command: $1"
    echo "Usage: mm help"
    exit 1
    ;;
esac
EOF

chmod +x "$MM_PATH"

# ── Load shared functions and config ─────────────────────
# From here on, everything runs from the repo location (TARGET_DIR).
# SCRIPTS_DIR in mm_common.sh then points to TARGET_DIR correctly.

source "$TARGET_DIR/mm_common.sh"
mkdir -p "$LOG_DIR"
trap 'record_script_result "mm_install.sh" "$?"' EXIT

echo
echo "── 🍺 Homebrew ───────────────────────────────────"

if ensure_brew; then
    log_ok "Homebrew available"
else
    log_warn "Homebrew installation failed"
    exit 1
fi

run_step "brew update" brew update

echo
echo "── ⚙️  Configuration ─────────────────────────────"

run_step "git global exclude setup" setup_git_global

# ── Install apps ─────────────────────

echo
echo "── 📦 Applications ───────────────────────────────"

CASK_PRESENT=0
CASK_INSTALLED=0
CASK_FAILED=0
CASK_FAILED_NAMES=""
for pkg in "${MANAGED_CASKS[@]}"; do
    if brew list --cask "$pkg" &>/dev/null; then
        CASK_PRESENT=$((CASK_PRESENT + 1))
    else
        echo "   Installing cask: $pkg"
        if brew install --cask "$pkg"; then
            CASK_INSTALLED=$((CASK_INSTALLED + 1))
        else
            CASK_FAILED=$((CASK_FAILED + 1))
            CASK_FAILED_NAMES="${CASK_FAILED_NAMES:+$CASK_FAILED_NAMES, }$pkg"
        fi
    fi
done

if [[ "$CASK_FAILED" -eq 0 ]]; then
    log_ok "Casks: $CASK_PRESENT already installed, $CASK_INSTALLED installed"
else
    log_warn "Casks: $CASK_PRESENT already installed, $CASK_INSTALLED installed, $CASK_FAILED failed ($CASK_FAILED_NAMES)"
fi

echo
echo "── 🧰 CLI tools ──────────────────────────────────"

TOOL_PRESENT=0
TOOL_INSTALLED=0
TOOL_FAILED=0
TOOL_FAILED_NAMES=""
for pkg in "${CLI_TOOLS[@]}"; do
    if brew list "$pkg" &>/dev/null; then
        TOOL_PRESENT=$((TOOL_PRESENT + 1))
    else
        echo "   Installing formula: $pkg"
        if brew install "$pkg"; then
            TOOL_INSTALLED=$((TOOL_INSTALLED + 1))
        else
            TOOL_FAILED=$((TOOL_FAILED + 1))
            TOOL_FAILED_NAMES="${TOOL_FAILED_NAMES:+$TOOL_FAILED_NAMES, }$pkg"
        fi
    fi
done

if [[ "$TOOL_FAILED" -eq 0 ]]; then
    log_ok "CLI tools: $TOOL_PRESENT already installed, $TOOL_INSTALLED installed"
else
    log_warn "CLI tools: $TOOL_PRESENT already installed, $TOOL_INSTALLED installed, $TOOL_FAILED failed ($TOOL_FAILED_NAMES)"
fi

run_step "brew cleanup" brew cleanup

echo
echo "── 🕰  Automation ────────────────────────────────"

write_auto_launch_agent

if load_auto_launch_agent; then
    log_ok "Auto-maintenance scheduled for Saturday $(printf '%02d:%02d' "$AUTO_HOUR" "$AUTO_MINUTE")"
else
    log_warn "Failed to load LaunchAgent"
fi

# ── iCloud bootstrap copy ───────────
sync_scripts_to_icloud

# ── Summary ──────────────────────────

summary_print

echo
echo "── 📁 Installation paths ─────────────────────────"
log_ok "Scripts: $TARGET_DIR"
log_ok "Symlink: $SYMLINK_PATH"
log_ok "Command: $MM_PATH"

if ! echo "$PATH" | tr ':' '\n' | grep -Fxq "$HOME/Scripts/bin"; then
    echo ""
    log_warn "Make sure ~/Scripts/bin is in your PATH (for example in ~/.zshrc or ~/.bash_profile):"
    echo '         export PATH="$HOME/Scripts/bin:$PATH"'
fi
