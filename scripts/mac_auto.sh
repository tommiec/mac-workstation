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

source "$HOME/Library/Application Support/mac-maintenance/mac_common.sh"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/auto_$(date '+%Y-%m-%d_%H-%M-%S').log") 2>&1

notify_user "Mac onderhoud gestart" "Automatische maintenance gestart."

echo "── ⚡ Auto onderhoud ──"

# ── Brew ─────────────────────────────

if command -v brew &>/dev/null; then
    run_step "brew update" brew update
    run_step "brew upgrade" brew upgrade --formula
    run_step "brew cleanup" brew cleanup --prune=30
    run_step "brew autoremove" brew autoremove
else
    log_warn "brew niet beschikbaar"
fi

# ── macOS updates ───────────────────

UPDATES="$(/usr/sbin/softwareupdate --list 2>/dev/null || true)"
COUNT=$(echo "$UPDATES" | grep -c "^\*" || true)

if [[ "$COUNT" -eq 0 ]]; then
    log_ok "Geen macOS updates"
else
    log_warn "$COUNT macOS update(s) beschikbaar"
    notify_user "macOS updates beschikbaar" "Gebruik mac_manual.sh om te installeren."
fi

# ── Cache cleanup ───────────────────

DELETED=$(/usr/bin/find "$HOME/Library/Caches" -type f -mtime +7 -print -delete 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
log_ok "$DELETED oude cachebestanden verwijderd"

notify_user "Mac onderhoud voltooid" "Maintenance afgerond."

summary_print