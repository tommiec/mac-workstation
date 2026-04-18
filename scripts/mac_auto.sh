#!/bin/bash
# =========================================================
# mac_auto.sh
# Wekelijkse automatische maintenance (launchd)
#
# Niet rechtstreeks uitvoeren — draait automatisch via
# launchd (geregistreerd door mac_install.sh).
# Schema: elke zaterdag om 02:00
#
# Wat dit script doet:
#   - Homebrew formulas updaten en opruimen
#   - macOS updates detecteren en melden via notificatie
#   - Oude cachebestanden (>7 dagen) verwijderen
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mac_common.sh"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/auto_$(date '+%Y-%m-%d_%H-%M-%S').log") 2>&1

notify_user "Mac onderhoud gestart" "Automatische maintenance gestart."

echo "── ⚡ Auto onderhoud ──"

# ── Brew ─────────────────────────────
# brew wordt gecontroleerd via command -v, niet via ensure_brew:
# in een nachtjob willen we geen interactieve Homebrew-installatie starten.

if command -v brew &>/dev/null; then
    run_step "brew update"     brew update
    run_step "brew upgrade"    brew upgrade --formula
    run_step "brew cleanup"    brew cleanup --prune=30
    run_step "brew autoremove" brew autoremove
else
    log_warn "brew niet beschikbaar — sla brew-stappen over"
fi

# ── macOS updates ────────────────────
# Enkel detecteren en melden; installatie gebeurt via 'mm manual'.
# softwareupdate --list schrijft naar stderr; 2>&1 vangt dit op.
# grep -c geeft exit 1 bij 0 matches; || echo 0 vangt dit op.

UPDATES="$(/usr/sbin/softwareupdate --list 2>&1 || true)"
COUNT=$(echo "$UPDATES" | grep -cE '^[[:space:]]*\*' || true)
COUNT=${COUNT:-0}

if [[ "$COUNT" -eq 0 ]]; then
    log_ok "Geen macOS updates beschikbaar"
else
    log_warn "$COUNT macOS update(s) beschikbaar"
    notify_user "macOS updates beschikbaar" "Gebruik 'mm manual' om te installeren."
fi

# ── Cache cleanup ────────────────────
# Verwijdert bestanden ouder dan 7 dagen uit ~/Library/Caches.
# Systeemmappen die door launchd-diensten actief gebruikt worden
# (bv. com.apple.bird voor iCloud) worden bewust niet uitgesloten:
# bestanden ouder dan 7 dagen zijn daar zelden in gebruik om 02:00.
# Pas de -mtime drempel aan indien je hier problemen mee ervaart.

DELETED=$(
    /usr/bin/find "$HOME/Library/Caches" \
        -type f -mtime +7 \
        -print -delete 2>/dev/null \
    | /usr/bin/wc -l \
    | /usr/bin/tr -d ' '
)
log_ok "$DELETED oude cachebestanden verwijderd"

notify_user "Mac onderhoud voltooid" "Maintenance afgerond."

summary_print