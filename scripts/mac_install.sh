#!/bin/bash
# =========================================================
# mac_install.sh
# Bootstrap setup script — installeert apps en configureert automation
#
# Gebruik (éénmalig op nieuwe Mac):
#   GitHub:
#     bash ~/Repositories/mac-maintenance/scripts/mac_install.sh
#   iCloud Drive:
#     bash ~/Library/Mobile\ Documents/com~apple~CloudDocs/Scripts/mac-maintenance/scripts/mac_install.sh
#
# Wat dit script doet:
#   1. Kopieert de maintenance-repo naar:
#        ~/Repositories/mac-maintenance
#   2. Maakt een symlink:
#        ~/Scripts/mac-maintenance -> ~/Repositories/mac-maintenance
#   3. Maakt een command wrapper:
#        ~/Scripts/bin/mm
#   4. Installeert Homebrew indien nodig
#   5. Installeert alle apps uit MANAGED_CASKS en CLI_TOOLS
#   6. Registreert mac_auto.sh als wekelijkse launchd-agent
#        (elke zaterdag om 02:00)
#
# Na installatie:
#   mm auto
#   mm manual
#   mm install
#   mm doctor
# =========================================================

set -o pipefail
set -u

# SRC_DIR = locatie van dit script (bv. iCloud Drive bij eerste run)
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_ROOT="$HOME/Repositories/mac-maintenance"
TARGET_DIR="$REPO_ROOT/scripts"
SCRIPTS_ROOT="$HOME/Scripts"
SYMLINK_PATH="$SCRIPTS_ROOT/mac-maintenance"
BIN_DIR="$SCRIPTS_ROOT/bin"
MM_PATH="$BIN_DIR/mm"

mkdir -p "$REPO_ROOT"
mkdir -p "$TARGET_DIR"
mkdir -p "$BIN_DIR"

echo "── 🚀 Installatie gestart ──"

# ── Scripts naar repo kopiëren ───────────────────────────
# Elke kopie wordt apart gelogd zodat fouten zichtbaar zijn.
# mac_install.sh kopieert zichzelf bewust mee, zodat 'mm install'
# altijd de meest recente versie vanuit de repo uitvoert.

COPY_OK=true
for f in mac_common.sh mac_auto.sh mac_manual.sh mac_install.sh mac_doctor.sh; do
    SRC="$SRC_DIR/$f"
    DST="$TARGET_DIR/$f"

    if cmp -s "$SRC" "$DST" 2>/dev/null; then
        echo "   ✔️ $f identiek (skip)"
    elif cp "$SRC" "$DST"; then
        echo "   ✅ $f gekopieerd"
    else
        echo "   ❌ $f kopiëren mislukt"
        COPY_OK=false
    fi
done

if [[ "$COPY_OK" == false ]]; then
    echo "❌ Niet alle scripts konden worden gekopieerd. Installatie afgebroken."
    exit 1
fi

chmod +x "$TARGET_DIR"/*.sh

# ── Symlink naar ~/Scripts/mac-maintenance ───────────────

ln -sfn "$REPO_ROOT" "$SYMLINK_PATH"

# ── Command wrapper mm aanmaken ──────────────────────────

cat > "$MM_PATH" <<'EOF'
#!/bin/zsh

case "$1" in
  auto)
    shift
    "$HOME/Scripts/mac-maintenance/scripts/mac_auto.sh" "$@"
    ;;
  manual)
    shift
    "$HOME/Scripts/mac-maintenance/scripts/mac_manual.sh" "$@"
    ;;
  install)
    shift
    "$HOME/Scripts/mac-maintenance/scripts/mac_install.sh" "$@"
    ;;
  doctor)
    shift
    "$HOME/Scripts/mac-maintenance/scripts/mac_doctor.sh" "$@"
    ;;
  help|"")
    echo "Gebruik:"
    echo "  mm auto     # automatische maintenance"
    echo "  mm manual   # manueel onderhoud"
    echo "  mm install  # setup uitvoeren"
    echo "  mm doctor   # setup controleren"
    ;;
  *)
    echo "Onbekend commando: $1"
    echo "Gebruik: mm help"
    exit 1
    ;;
esac
EOF

chmod +x "$MM_PATH"

# ── Gedeelde functies en config laden ────────────────────
# Vanaf hier loopt alles vanuit de repo-locatie (TARGET_DIR).
# SCRIPTS_DIR in mac_common.sh wijst dan correct naar TARGET_DIR.

source "$TARGET_DIR/mac_common.sh"
mkdir -p "$LOG_DIR"

# ── Homebrew ─────────────────────────

if ensure_brew; then
    log_ok "Homebrew beschikbaar"
else
    log_warn "Homebrew installatie mislukt"
    exit 1
fi

run_step "brew update" brew update

# ── Apps installeren ─────────────────

for pkg in "${MANAGED_CASKS[@]}"; do
    if brew list --cask "$pkg" &>/dev/null; then
        log_ok "$pkg al aanwezig"
    else
        run_step "$pkg installeren" brew install --cask "$pkg"
    fi
done

for pkg in "${CLI_TOOLS[@]}"; do
    if brew list "$pkg" &>/dev/null; then
        log_ok "$pkg al aanwezig"
    else
        run_step "$pkg installeren" brew install "$pkg"
    fi
done

run_step "brew cleanup" brew cleanup

# ── LaunchAgent ─────────────────────

write_auto_launch_agent

if load_auto_launch_agent; then
    log_ok "Auto-maintenance ingepland voor zaterdag $(printf '%02d:%02d' "$AUTO_HOUR" "$AUTO_MINUTE")"
else
    log_warn "LaunchAgent laden mislukt"
fi

# ── iCloud bootstrap copy ───────────
sync_scripts_to_icloud

# ── Samenvatting ─────────────────────

summary_print

echo
echo "── 📁 Installatiepaden ───────────────────────────"
log_ok "Repo:    $REPO_ROOT"
log_ok "Symlink: $SYMLINK_PATH"
log_ok "Command: $MM_PATH"

if ! echo "$PATH" | tr ':' '\n' | grep -Fxq "$HOME/Scripts/bin"; then
    echo ""
    log_warn "Zorg dat ~/Scripts/bin in je PATH staat (bv. in ~/.zshrc of ~/.bash_profile):"
    echo '         export PATH="$HOME/Scripts/bin:$PATH"'
fi