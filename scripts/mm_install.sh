#!/bin/bash
# =========================================================
# mm_install.sh
# Bootstrap setup script — installs apps and configures Mac Manager automation
#
# Usage (once on a new Mac):
#   bash ~/Repositories/dev/mac-workstation/scripts/mm_install.sh
#
# What this script does:
#   1. Creates a command wrapper:
#        ~/.local/bin/mm
#   2. Installs Homebrew if needed
#   3. Installs all apps from MANAGED_CASKS and CLI_TOOLS
#   4. Registers mm_auto.sh as a weekly launchd agent
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

REPO_ROOT="$HOME/Repositories/dev/mac-workstation"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
MM_PATH="$BIN_DIR/mm"
ZSHRC_PATH="$HOME/.zshrc"

echo "── 🚀 Installation started ──"

if [[ "$SCRIPT_DIR" != "$REPO_ROOT/scripts" || ! -d "$REPO_ROOT/.git" ]]; then
    echo "❌ Run this installer from the canonical Git checkout:"
    echo "   $REPO_ROOT/scripts/mm_install.sh"
    exit 1
fi

mkdir -p "$BIN_DIR"
chmod +x "$SCRIPT_DIR"/*.sh

# ── Create mm command wrapper ────────────────────────────

cat > "$MM_PATH" <<'EOF'
#!/bin/zsh

MM_SCRIPTS_DIR="$HOME/Repositories/dev/mac-workstation/scripts"

case "$1" in
  auto)
    shift
    "$MM_SCRIPTS_DIR/mm_auto.sh" "$@"
    ;;
  maintain)
    shift
    "$MM_SCRIPTS_DIR/mm_maintain.sh" "$@"
    ;;
  install)
    shift
    "$MM_SCRIPTS_DIR/mm_install.sh" "$@"
    ;;
  doctor)
    shift
    "$MM_SCRIPTS_DIR/mm_doctor.sh" "$@"
    ;;
  triage)
    shift
    "$MM_SCRIPTS_DIR/mm_triage.sh" "$@"
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

source "$SCRIPT_DIR/mm_common.sh"
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

setup_mm_command_path() {
    # Literal line written to ~/.zshrc; expansion must happen in future shells.
    # shellcheck disable=SC2016
    local path_line='export PATH="$HOME/.local/bin:$PATH"'

    touch "$ZSHRC_PATH" || return 1
    if ! grep -Fqx "$path_line" "$ZSHRC_PATH"; then
        if [[ -s "$ZSHRC_PATH" ]]; then
            echo "" >> "$ZSHRC_PATH" || return 1
        fi
        {
            echo "# Mac Manager CLI"
            echo "$path_line"
        } >> "$ZSHRC_PATH" || return 1
    fi

    export PATH="$BIN_DIR:$PATH"
}

run_step "mm command PATH setup" setup_mm_command_path
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

# ── Summary ──────────────────────────

summary_print

echo
echo "── 📁 Installation paths ─────────────────────────"
log_ok "Scripts: $SCRIPT_DIR"
log_ok "Command: $MM_PATH"

if ! echo "$PATH" | tr ':' '\n' | grep -Fxq "$BIN_DIR"; then
    echo ""
    log_warn "Make sure ~/.local/bin is in your PATH (for example in ~/.zshrc or ~/.bash_profile):"
    # shellcheck disable=SC2016
    echo '         export PATH="$HOME/.local/bin:$PATH"'
fi
