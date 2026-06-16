#!/bin/bash
# =========================================================
# mm_install.sh
# Bootstrap setup script — installs apps and configures Mac Manager automation
#
# Usage (once on a new Mac):
#   GitHub:
#     bash ~/Repositories/mac-workstation/scripts/mm_install.sh
#   iCloud Drive:
#     bash ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts/mac-workstation/scripts/mm_install.sh
#
# What this script does:
#   1. Copies the Mac Manager scripts to:
#        ~/Repositories/mac-workstation/scripts
#   2. Creates a symlink:
#        ~/Scripts/mac-workstation -> ~/Repositories/mac-workstation
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

REPO_ROOT="$HOME/Repositories/mac-workstation"
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
# Each copy is logged separately so errors are visible.
# mm_install.sh intentionally copies itself, so 'mm install'
# always runs the latest installed version.

COPY_OK=true
for f in mm_common.sh mm_auto.sh mm_maintain.sh mm_install.sh mm_doctor.sh mm_triage.sh; do
    SRC="$SRC_DIR/$f"
    DST="$TARGET_DIR/$f"

    if cmp -s "$SRC" "$DST" 2>/dev/null; then
        echo "   ✔️ $f identical (skipped)"
    elif cp "$SRC" "$DST"; then
        echo "   ✅ $f copied"
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
    echo "  mm maintain  # run maintenance now"
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
trap 'status=$?; record_script_result "mm_install.sh" "$status"' EXIT

# ── Homebrew ─────────────────────────

if ensure_brew; then
    log_ok "Homebrew available"
else
    log_warn "Homebrew installation failed"
    exit 1
fi

run_step "brew update" brew update

# ── Install apps ─────────────────────

for pkg in "${MANAGED_CASKS[@]}"; do
    if brew list --cask "$pkg" &>/dev/null; then
        log_ok "$pkg already installed"
    else
        run_step "install $pkg" brew install --cask "$pkg"
    fi
done

for pkg in "${CLI_TOOLS[@]}"; do
    if brew list "$pkg" &>/dev/null; then
        log_ok "$pkg already installed"
    else
        run_step "install $pkg" brew install "$pkg"
    fi
done

run_step "brew cleanup" brew cleanup

# ── LaunchAgent ─────────────────────

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
