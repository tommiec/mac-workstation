#!/bin/bash
# =========================================================
# mac_manual.sh
# Handmatig onderhoud en systeemcontrole
#
# Gebruik (na installatie):
#   mm manual
#   of
#   bash ~/Scripts/mac-maintenance/scripts/mac_manual.sh
#
# Wat dit script doet:
#   - brew doctor uitvoeren
#   - DNS-cache flushen
#   - macOS updates detecteren en optioneel installeren
#
# Vereist sudo (wordt éénmalig gevraagd bij opstart).
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mac_common.sh"

# ── Sudo ─────────────────────────────
# sudo -v vraagt het wachtwoord éénmalig op en valideert de sessie.
# De keepalive-loop verlengt de sudo-timestamp elke 50 seconden,
# zodat langlopende stappen (bv. softwareupdate) niet blokkeren.

if ! sudo -v; then
    echo "Sudo mislukt — script afgebroken."
    exit 1
fi

while true; do
    sudo -n true
    sleep 50
    kill -0 "$$" || exit
done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/manual_$(date '+%Y-%m-%d_%H-%M-%S').log") 2>&1

notify_user "Mac onderhoud gestart" "Manuele maintenance gestart."

echo "── 🔍 Manueel onderhoud ──"

# ── Brew doctor ──────────────────────
# brew doctor geeft exit 0 bij een gezond systeem, anders exit 1.
# We tonen de volledige output en loggen op basis van de exit code,
# niet via grep op de output (robuuster bij taalvariaties in Homebrew).

if brew doctor; then
    log_ok "brew doctor OK"
else
    log_warn "brew doctor gaf waarschuwingen — zie output hierboven"
fi

# ── DNS flush ────────────────────────

if sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder; then
    log_ok "DNS-cache geleegd"
else
    log_warn "DNS flush mislukt"
fi

# ── macOS updates ────────────────────
# grep -c geeft exit 1 bij 0 matches; de subshell vangt dit op met || echo 0.

UPDATES="$(/usr/sbin/softwareupdate --list 2>&1 || true)"
echo "$UPDATES"

COUNT=$(echo "$UPDATES" | grep -cE '^[[:space:]]*\*' || true)
COUNT=${COUNT:-0}

if [[ "$COUNT" -eq 0 ]]; then
    log_ok "Geen macOS updates beschikbaar"
else
    log_warn "$COUNT macOS update(s) beschikbaar"

    read -r -p "   Updates installeren? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        INSTALL_OUT="$(sudo /usr/sbin/softwareupdate --install --all 2>&1 || true)"
        echo "$INSTALL_OUT"

        if echo "$INSTALL_OUT" | grep -q "No updates are available"; then
            log_info "Geen updates meer beschikbaar"
        elif echo "$INSTALL_OUT" | grep -qiE "installed|Done|restart"; then
            log_ok "Updates uitgevoerd"
        else
            log_warn "Update resultaat onduidelijk — controleer output hierboven"
        fi
    else
        log_info "Updates overgeslagen"
    fi
fi

notify_user "Mac onderhoud voltooid" "Manuele maintenance afgerond."

summary_print