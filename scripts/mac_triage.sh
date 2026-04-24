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
FILE_INFO=$(file "$FILE")
echo "$FILE_INFO"
SIZE=$(stat -f%z "$FILE" 2>/dev/null || wc -c < "$FILE")
echo "Grootte: $SIZE bytes"

case "$FILE" in
    *.exe|*.dll|*.ps1|*.bat|*.cmd|*.vbs|*.js|*.jar)
        add_warn "Uitvoerbare of scriptachtige extensie gedetecteerd."
        ;;
esac

if echo "$FILE_INFO" | grep -qi "CRLF"; then
    add_warn "CRLF line endings gevonden. Dit kan scripts breken op macOS/Linux."
fi

# ── Heuristic: extensie vs file utility ──────────────────
EXTENSION="${FILE##*.}"
EXTENSION=$(echo "$EXTENSION" | tr '[:upper:]' '[:lower:]')

if echo "$FILE_INFO" | grep -qi "executable"; then
    case "$EXTENSION" in
        txt|jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx)
            add_warn "Bestandsextensie ($EXTENSION) komt niet overeen met executable inhoud. Mogelijk vermomd bestand."
            ;;
    esac
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
MAGIC_HEAD=$(printf '%s' "$MAGIC" | cut -c1-8)
echo "Eerste bytes: ${MAGIC:-onbekend}"

case "$MAGIC" in
    4D5A*)
        add_warn "MZ-header gevonden: Windows PE executable/DLL."
        if ! echo "$FILE_INFO" | grep -Eqi "PE|MS-DOS|executable"; then
            add_warn "MZ-header gevonden maar file utility herkent geen executable. Verdacht of corrupte binary."
        fi
        ;;
    7F454C46*)
        add_warn "ELF-header gevonden: Linux binary."
        if ! echo "$FILE_INFO" | grep -qi "ELF"; then
            add_warn "ELF-magic bytes gevonden maar file utility herkent geen ELF. Mogelijk vermomd of corrupt bestand."
        fi
        ;;
    CAFEBABE*)
        add_warn "Java class/JAR-indicator gevonden."
        if ! echo "$FILE_INFO" | grep -Eqi "Java|class"; then
            add_warn "Java magic bytes gevonden maar file utility herkent geen Java class. Mogelijk vermomd of corrupt bestand."
        fi
        ;;
    25504446*)
        echo -e "${BLUE}ℹ️  PDF-header gevonden.${NC}"
        if ! echo "$FILE_INFO" | grep -qi "PDF"; then
            add_warn "PDF-magic bytes gevonden maar file utility herkent geen PDF. Mogelijk vermomd of corrupt bestand."
        fi
        ;;
    89504E47*)
        echo -e "${BLUE}ℹ️  PNG-header gevonden.${NC}"
        if ! echo "$FILE_INFO" | grep -qi "PNG"; then
            add_warn "PNG-magic bytes gevonden maar file utility herkent geen PNG. Mogelijk vermomd of corrupt bestand."
        fi
        ;;
    FFD8FF*)
        echo -e "${BLUE}ℹ️  JPEG-header gevonden.${NC}"
        if ! echo "$FILE_INFO" | grep -Eqi "JPEG|JPG"; then
            add_warn "JPEG-magic bytes gevonden maar file utility herkent geen JPEG. Mogelijk vermomd of corrupt bestand."
        fi
        ;;
    *)
        echo -e "${BLUE}ℹ️  Geen bekende magic byte uit de basislijst.${NC}"
        ;;
esac

# ── Heuristic: extensie vs magic bytes ───────────────────
case "$EXTENSION:$MAGIC_HEAD" in
    jpg:4D5A*|jpeg:4D5A*|png:4D5A*|gif:4D5A*|pdf:4D5A*|txt:4D5A*)
        add_warn "Extensie .$EXTENSION maar MZ/Windows-executable magic bytes gevonden. Sterk verdacht."
        ;;
    exe:25504446*|dll:25504446*)
        add_warn "Extensie .$EXTENSION maar PDF magic bytes gevonden. Bestandstype klopt mogelijk niet."
        ;;
    exe:89504E47*|dll:89504E47*)
        add_warn "Extensie .$EXTENSION maar PNG magic bytes gevonden. Bestandstype klopt mogelijk niet."
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