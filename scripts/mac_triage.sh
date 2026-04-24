#!/bin/bash
# =========================================================
# mac_triage.sh
# Snelle malware/file triage met hash, VirusTotal, hex,
# strings, IOC-extractie en eenvoudige scoring.
#
# Gebruik:
#   mm triage bestand.exe
# =========================================================

set -o pipefail
set -u

if [ $# -ne 1 ]; then
    echo "Gebruik: mm triage <bestand>"
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "❌ Bestand niet gevonden: $FILE"
    exit 1
fi

# ── Kleuren ──────────────────────────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    YELLOW=''
    GREEN=''
    BLUE=''
    BOLD=''
    NC=''
fi

score=0
warn_count=0

add_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    score=$((score + 1))
    warn_count=$((warn_count + 1))
}

section() {
    echo
    echo -e "${BOLD}== $1 ==${NC}"
}

echo -e "${BOLD}── 🔎 File triage v2 ──${NC}"
echo

# ── Basisinfo ────────────────────────────────────────────
section "Bestand"
file "$FILE"
SIZE=$(stat -f%z "$FILE" 2>/dev/null || wc -c < "$FILE")
echo "Grootte: $SIZE bytes"

case "$FILE" in
    *.exe|*.dll|*.ps1|*.bat|*.cmd|*.vbs|*.js|*.jar)
        add_warn "Uitvoerbare of scriptachtige extensie gedetecteerd."
        ;;
esac

if file "$FILE" | grep -qi "CRLF"; then
    add_warn "CRLF line endings gevonden. Dit kan scripts breken op macOS/Linux."
fi

# ── Hash ─────────────────────────────────────────────────
section "SHA256"
HASH=$(shasum -a 256 "$FILE" | awk '{print $1}')
echo "$HASH"

# ── VirusTotal ───────────────────────────────────────────
section "VirusTotal lookup"
if command -v vt >/dev/null 2>&1; then
    if vt file "$HASH"; then
        echo -e "${GREEN}✅ VirusTotal lookup uitgevoerd.${NC}"
    else
        add_warn "Geen VirusTotal-resultaat of lookup mislukt. Onbekend betekent niet veilig."
    fi
else
    add_warn "vt CLI niet gevonden."
fi

# ── Hex preview ──────────────────────────────────────────
section "Hex preview"
if command -v hexdump >/dev/null 2>&1; then
    hexdump -C "$FILE" | head -n 16
elif command -v xxd >/dev/null 2>&1; then
    xxd "$FILE" | head -n 16
else
    add_warn "hexdump/xxd niet gevonden."
fi

# ── Magic bytes ──────────────────────────────────────────
section "Magic bytes"
MAGIC=$(xxd -p -l 8 "$FILE" 2>/dev/null | tr '[:lower:]' '[:upper:]')
echo "Eerste bytes: ${MAGIC:-onbekend}"

case "$MAGIC" in
    4D5A*)
        add_warn "MZ-header gevonden: Windows PE executable/DLL."
        ;;
    7F454C46*)
        add_warn "ELF-header gevonden: Linux binary."
        ;;
    CAFEBABE*)
        add_warn "Java class/JAR-indicator gevonden."
        ;;
    25504446*)
        echo -e "${BLUE}ℹ️  PDF-header gevonden.${NC}"
        ;;
    89504E47*)
        echo -e "${BLUE}ℹ️  PNG-header gevonden.${NC}"
        ;;
    FFD8FF*)
        echo -e "${BLUE}ℹ️  JPEG-header gevonden.${NC}"
        ;;
    *)
        echo -e "${BLUE}ℹ️  Geen bekende magic byte uit de basislijst.${NC}"
        ;;
esac

# ── Quick indicators ─────────────────────────────────────
section "Quick indicators"
TMP_STRINGS=$(mktemp)
strings -n 6 "$FILE" > "$TMP_STRINGS"

IOC_REGEX='(https?://|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|([0-9]{1,3}\.){3}[0-9]{1,3}|powershell|cmd\.exe|/bin/bash|/bin/sh|/dev/tcp|nc -|curl |wget |base64|eval\(|exec\(|os\.system|pickle\.loads)'

if grep -Eai "$IOC_REGEX" "$TMP_STRINGS" | head -n 30; then
    add_warn "Mogelijke IOC's of verdachte strings gevonden. Bekijk de output hierboven."
else
    echo -e "${GREEN}✅ Geen snelle IOC-hit in strings.${NC}"
fi

# ── Score ────────────────────────────────────────────────
section "Triage score"
if [ "$score" -eq 0 ]; then
    echo -e "${GREEN}Score: $score — geen duidelijke signalen in snelle triage.${NC}"
elif [ "$score" -le 2 ]; then
    echo -e "${YELLOW}Score: $score — verder bekijken aanbevolen.${NC}"
else
    echo -e "${RED}Score: $score — verdacht genoeg voor diepere analyse in VM/sandbox.${NC}"
fi

echo "Waarschuwingen: $warn_count"

# ── Strings ──────────────────────────────────────────────
section "Strings"
echo "Druk op q om te stoppen."
less "$TMP_STRINGS"

rm -f "$TMP_STRINGS"