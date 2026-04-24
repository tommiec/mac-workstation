#!/bin/bash
# =========================================================
# mac_triage.sh
# Quick malware/file triage with hash, VirusTotal, hex,
# strings, IOC extraction and simple scoring.
#
# Usage:
#   mm triage file.exe
# =========================================================

set -o pipefail
set -u

if [ $# -ne 1 ]; then
    echo "Usage: mm triage <file>"
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "❌ File not found: $FILE"
    exit 1
fi

# ── Colors ───────────────────────────────────────────────
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

# ── Basic info ───────────────────────────────────────────
section "File"
FILE_INFO=$(file "$FILE")
echo "$FILE_INFO"
SIZE=$(stat -f%z "$FILE" 2>/dev/null || wc -c < "$FILE")
echo "Size: $SIZE bytes"

case "$FILE" in
    *.exe|*.dll|*.ps1|*.bat|*.cmd|*.vbs|*.js|*.jar)
        add_warn "Executable or script-like extension detected."
        ;;
esac

if echo "$FILE_INFO" | grep -qi "CRLF"; then
    add_warn "CRLF line endings found. This can break scripts on macOS/Linux."
fi

# ── Heuristic: extension vs file utility ─────────────────
EXTENSION="${FILE##*.}"
EXTENSION=$(echo "$EXTENSION" | tr '[:upper:]' '[:lower:]')

if echo "$FILE_INFO" | grep -qi "executable"; then
    case "$EXTENSION" in
        txt|jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx)
            add_warn "File extension ($EXTENSION) does not match executable content. Possibly disguised file."
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
        echo -e "${GREEN}✅ VirusTotal lookup completed.${NC}"
    else
        add_warn "No VirusTotal result or lookup failed. Unknown does not mean safe."
    fi
else
    add_warn "vt CLI not found."
fi

# ── Hex preview ──────────────────────────────────────────
section "Hex preview"
if command -v hexdump >/dev/null 2>&1; then
    hexdump -C "$FILE" | head -n 16
elif command -v xxd >/dev/null 2>&1; then
    xxd "$FILE" | head -n 16
else
    add_warn "hexdump/xxd not found."
fi

# ── Magic bytes ──────────────────────────────────────────
section "Magic bytes"
MAGIC=$(xxd -p -l 8 "$FILE" 2>/dev/null | tr '[:lower:]' '[:upper:]')
MAGIC_HEAD=$(printf '%s' "$MAGIC" | cut -c1-8)
echo "First bytes: ${MAGIC:-unknown}"

case "$MAGIC" in
    4D5A*)
        add_warn "MZ header found: Windows PE executable/DLL."
        if ! echo "$FILE_INFO" | grep -Eqi "PE|MS-DOS|executable"; then
            add_warn "MZ header found, but the file utility does not recognize an executable. Suspicious or corrupt binary."
        fi
        ;;
    7F454C46*)
        add_warn "ELF header found: Linux binary."
        if ! echo "$FILE_INFO" | grep -qi "ELF"; then
            add_warn "ELF magic bytes found, but the file utility does not recognize ELF. Possibly disguised or corrupt file."
        fi
        ;;
    CAFEBABE*)
        add_warn "Java class/JAR indicator found."
        if ! echo "$FILE_INFO" | grep -Eqi "Java|class"; then
            add_warn "Java magic bytes found, but the file utility does not recognize a Java class. Possibly disguised or corrupt file."
        fi
        ;;
    25504446*)
        echo -e "${BLUE}ℹ️  PDF header found.${NC}"
        if ! echo "$FILE_INFO" | grep -qi "PDF"; then
            add_warn "PDF magic bytes found, but the file utility does not recognize PDF. Possibly disguised or corrupt file."
        fi
        ;;
    89504E47*)
        echo -e "${BLUE}ℹ️  PNG header found.${NC}"
        if ! echo "$FILE_INFO" | grep -qi "PNG"; then
            add_warn "PNG magic bytes found, but the file utility does not recognize PNG. Possibly disguised or corrupt file."
        fi
        ;;
    FFD8FF*)
        echo -e "${BLUE}ℹ️  JPEG header found.${NC}"
        if ! echo "$FILE_INFO" | grep -Eqi "JPEG|JPG"; then
            add_warn "JPEG magic bytes found, but the file utility does not recognize JPEG. Possibly disguised or corrupt file."
        fi
        ;;
    *)
        echo -e "${BLUE}ℹ️  No known magic byte from the basic list.${NC}"
        ;;
esac

# ── Heuristic: extension vs magic bytes ──────────────────
case "$EXTENSION:$MAGIC_HEAD" in
    jpg:4D5A*|jpeg:4D5A*|png:4D5A*|gif:4D5A*|pdf:4D5A*|txt:4D5A*)
        add_warn "Extension .$EXTENSION, but MZ/Windows executable magic bytes found. Strongly suspicious."
        ;;
    exe:25504446*|dll:25504446*)
        add_warn "Extension .$EXTENSION, but PDF magic bytes found. File type may not match."
        ;;
    exe:89504E47*|dll:89504E47*)
        add_warn "Extension .$EXTENSION, but PNG magic bytes found. File type may not match."
        ;;
esac

# ── Quick indicators ─────────────────────────────────────
section "Quick indicators"
TMP_STRINGS=$(mktemp)
strings -n 6 "$FILE" > "$TMP_STRINGS"

IOC_REGEX='(https?://|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|([0-9]{1,3}\.){3}[0-9]{1,3}|powershell|cmd\.exe|/bin/bash|/bin/sh|/dev/tcp|nc -|curl |wget |base64|eval\(|exec\(|os\.system|pickle\.loads)'

if grep -Eai "$IOC_REGEX" "$TMP_STRINGS" | head -n 30; then
    add_warn "Possible IOCs or suspicious strings found. Review the output above."
else
    echo -e "${GREEN}✅ No quick IOC hits in strings.${NC}"
fi

# ── Score ────────────────────────────────────────────────
section "Triage score"
if [ "$score" -eq 0 ]; then
    echo -e "${GREEN}Score: $score — no clear signals in quick triage.${NC}"
elif [ "$score" -le 2 ]; then
    echo -e "${YELLOW}Score: $score — further review recommended.${NC}"
else
    echo -e "${RED}Score: $score — suspicious enough for deeper analysis in a VM/sandbox.${NC}"
fi

echo "Warnings: $warn_count"

# ── Strings ──────────────────────────────────────────────
section "Strings"
echo "Press q to stop."
less "$TMP_STRINGS"

rm -f "$TMP_STRINGS"
