#!/bin/bash
# =========================================================
# mac_manual.sh
# Handmatig onderhoud en systeemcontrole
#
# Gebruik (na installatie):
#   bash ~/Library/Application\ Support/mac-maintenance/\
#        mac_manual.sh
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

source "$HOME/Library/Application Support/mac-maintenance/mac_common.sh"

# ── Sudo ─────────────────────────────

if ! sudo -v; then
    echo "Sudo mislukt"
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

echo "── 🔍 Manueel onderhoud ──"

# ── Brew doctor ─────────────────────

OUT="$(brew doctor 2>&1)"
echo "$OUT"

if echo "$OUT" | grep -qi "Warning:"; then
    log_warn "brew doctor gaf waarschuwingen"
else
    log_ok "brew doctor OK"
fi

# ── DNS flush ───────────────────────

if sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder; then
    log_ok "DNS geflushed"
else
    log_warn "DNS flush mislukt"
fi

# ── macOS updates ───────────────────

UPDATES="$(/usr/sbin/softwareupdate --list 2>&1 || true)"
echo "$UPDATES"

COUNT=$(echo "$UPDATES" | grep -c "^\*" || true)

if [[ "$COUNT" -eq 0 ]]; then
    log_ok "Geen macOS updates"
else
    log_warn "$COUNT macOS update(s) beschikbaar"

    read -r -p "Updates installeren? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        OUT="$(sudo /usr/sbin/softwareupdate --install --all 2>&1 || true)"
        echo "$OUT"

        if echo "$OUT" | grep -q "No updates are available"; then
            log_info "Geen updates meer"
        elif echo "$OUT" | grep -qiE "installed|Done|restart"; then
            log_ok "Updates uitgevoerd"
        else
            log_warn "Update resultaat onduidelijk"
        fi
    else
        log_info "Updates overgeslagen"
    fi
fi

summary_print