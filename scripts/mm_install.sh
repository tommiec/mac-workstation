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
#   3. Installs all apps and CLI tools from the Brewfile (brew bundle)
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
  auto|maintain|install|doctor|triage)
    MM_CMD="$1"
    shift
    exec "$MM_SCRIPTS_DIR/mm_${MM_CMD}.sh" "$@"
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
# The full app and CLI tool list is declarative in the Brewfile; brew bundle
# installs what is missing. --no-upgrade: upgrades belong to mm maintain/auto.

echo
echo "── 📦 Applications & CLI tools ───────────────────"

if [[ -f "$BREWFILE" ]]; then
    run_step "brew bundle install (Brewfile)" \
        brew bundle install --file "$BREWFILE" --no-upgrade
else
    log_warn "Brewfile not found: $BREWFILE"
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
