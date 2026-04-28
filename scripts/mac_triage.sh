#!/bin/bash
# =========================================================
# mac_triage.sh
# Snelle static file/malware triage voor:
#
#   mm triage <file>
#
# Doel: handig voor een student/analyst. Geen uploads.
# VirusTotal doet alleen hash lookup via de vt CLI.
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mac_common.sh"

TMP_DIR=""

cleanup() {
    status="$1"
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
    record_script_result "mac_triage.sh" "$status"
}

trap 'status=$?; cleanup "$status"' EXIT

if [ $# -ne 1 ]; then
    echo "Usage: mm triage <file>"
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "❌ File not found: $FILE"
    exit 1
fi

# ── Kleuren ─────────────────────────────────────────────
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

section() {
    echo
    echo -e "${BOLD}== $1 ==${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    score=$((score + 1))
    warn_count=$((warn_count + 1))
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

ok() {
    echo -e "${GREEN}✅ $1${NC}"
}

have() {
    command -v "$1" >/dev/null 2>&1
}

maybe_less() {
    preview_file="$1"
    label="$2"

    if [ -t 0 ] && [ -t 1 ] && have less && [ -s "$preview_file" ]; then
        echo
        echo "Open full $label in less? [y/N]"
        read -r answer
        case "$answer" in
            y|Y|yes|YES) less "$preview_file" ;;
        esac
    fi
}

score=0
warn_count=0
ioc_count=0
keyword_count=0

type_label="unknown"
is_text=0
is_zip=0
is_pdf=0
is_docx=0
is_xlsx=0
is_pptx=0
is_jar=0

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mac_triage.XXXXXX")" || {
    echo "❌ Could not create temporary directory."
    exit 1
}

STRINGS_FILE="$TMP_DIR/strings.txt"
ZIP_LIST="$TMP_DIR/zip-list.txt"
HITS_FILE="$TMP_DIR/hits.txt"
CORE_XML="$TMP_DIR/core.xml"

echo -e "${BOLD}── 🔎 File triage v3 ──${NC}"

# ── FILE ────────────────────────────────────────────────
section "FILE"

filename="$(basename "$FILE")"
extension="(none)"
if echo "$filename" | grep -q '\.'; then
    extension="$(printf '%s' "${filename##*.}" | tr '[:upper:]' '[:lower:]')"
fi

if have file; then
    file_info="$(file "$FILE" 2>/dev/null || true)"
else
    file_info="$FILE: file utility not found"
    warn "file utility not found; type detection is limited."
fi

if stat -f%z "$FILE" >/dev/null 2>&1; then
    size="$(stat -f%z "$FILE")"
elif stat -c%s "$FILE" >/dev/null 2>&1; then
    size="$(stat -c%s "$FILE")"
else
    size="$(wc -c < "$FILE" | tr -d ' ')"
fi

echo "Path: $FILE"
echo "Name: $filename"
echo "Size: $size bytes"
echo "Extension: $extension"
echo "$file_info"

case "$extension" in
    exe|dll|scr|sys|ps1|bat|cmd|vbs|js|jse|wsf|jar|class|sh|bash|zsh|py|pl|rb|php|run|bin|elf|so)
        warn "Executable or script-like extension detected."
        ;;
esac

if echo "$file_info" | grep -qi "CRLF"; then
    warn "CRLF line endings found. Dit kan scripts op macOS/Linux breken of Windows-origin verraden."
fi

if echo "$file_info" | grep -Eqi 'text|script|JSON|XML|CSV|HTML|ASCII|UTF-8|Unicode'; then
    is_text=1
fi

# ── HASH ────────────────────────────────────────────────
section "HASH"

hash=""
if have shasum; then
    hash="$(shasum -a 256 "$FILE" | awk '{print $1}')"
elif have sha256sum; then
    hash="$(sha256sum "$FILE" | awk '{print $1}')"
else
    warn "No SHA256 tool found (shasum/sha256sum)."
fi

if [ -n "$hash" ]; then
    echo "SHA256: $hash"
fi

# ── VIRUSTOTAL ──────────────────────────────────────────
section "VIRUSTOTAL"

if [ -z "$hash" ]; then
    warn "No hash available; VirusTotal lookup skipped."
elif have vt; then
    echo "Running hash lookup only: vt file $hash"
    if vt file "$hash"; then
        ok "VirusTotal lookup completed."
    else
        warn "VirusTotal hash lookup failed or no result was returned. Unknown does not mean safe."
    fi
else
    warn "vt CLI not found. Skipping VirusTotal lookup; script continues."
fi

# ── MAGIC BYTES ─────────────────────────────────────────
section "MAGIC BYTES"

magic=""
if have xxd; then
    magic="$(xxd -p -l 16 "$FILE" 2>/dev/null | tr '[:lower:]' '[:upper:]')"
elif have hexdump; then
    magic="$(hexdump -v -e '16/1 "%02X"' -n 16 "$FILE" 2>/dev/null)"
else
    warn "No xxd/hexdump available for magic byte extraction."
fi

magic4="$(printf '%s' "$magic" | cut -c1-8)"
echo "First 16 bytes: ${magic:-unknown}"

case "$magic" in
    4D5A*)
        type_label="Windows PE / MZ executable"
        warn "MZ header found: Windows PE executable/DLL. Niet uitvoeren op je host."
        if ! echo "$file_info" | grep -Eqi 'PE|MS-DOS|executable'; then
            warn "MZ magic bytes gevonden, maar file(1) herkent geen executable. Mogelijk vermomd, corrupt of gepackt."
        fi
        ;;
    7F454C46*)
        type_label="ELF executable"
        warn "ELF header found: Linux binary. Behandel als uitvoerbare code."
        if ! echo "$file_info" | grep -qi 'ELF'; then
            warn "ELF magic bytes gevonden, maar file(1) herkent geen ELF. Mogelijk vermomd of corrupt."
        fi
        ;;
    25504446*)
        type_label="PDF document"
        is_pdf=1
        info "PDF header found."
        if ! echo "$file_info" | grep -qi 'PDF'; then
            warn "PDF magic bytes gevonden, maar file(1) herkent geen PDF. Controleer op polyglot/corrupt bestand."
        fi
        ;;
    504B0304*|504B0506*|504B0708*)
        type_label="ZIP container"
        is_zip=1
        info "ZIP header found. Dit kan ook DOCX/XLSX/PPTX/JAR zijn."
        ;;
    89504E47*)
        type_label="PNG image"
        info "PNG header found."
        if ! echo "$file_info" | grep -qi 'PNG'; then
            warn "PNG magic bytes gevonden, maar file(1) herkent geen PNG."
        fi
        ;;
    FFD8FF*)
        type_label="JPEG image"
        info "JPEG header found."
        if ! echo "$file_info" | grep -Eqi 'JPEG|JPG'; then
            warn "JPEG magic bytes gevonden, maar file(1) herkent geen JPEG."
        fi
        ;;
    CAFEBABE*)
        type_label="Java class"
        warn "Java class magic found. Dit is bytecode en kan uitvoerbare logica bevatten."
        ;;
    *)
        info "No known magic byte from the basic triage list."
        ;;
esac

# ── HEX PREVIEW ─────────────────────────────────────────
section "HEX PREVIEW"

if have hexdump; then
    hexdump -C "$FILE" | head -n 16
elif have xxd; then
    xxd "$FILE" | head -n 16
else
    warn "hexdump/xxd not found; cannot show hex preview."
fi

# ── ZIP / DOCX / XLSX / PPTX / JAR herkenning ───────────
if [ "$is_zip" -eq 1 ] && have unzip; then
    unzip -l "$FILE" > "$ZIP_LIST" 2>/dev/null || true

    if grep -Eq '(^|[[:space:]])\[Content_Types\]\.xml$' "$ZIP_LIST"; then
        if grep -Eq '(^|[[:space:]])word/' "$ZIP_LIST"; then
            type_label="DOCX / Word OOXML document"
            is_docx=1
            info "ZIP internals contain word/ and [Content_Types].xml: likely DOCX."
        elif grep -Eq '(^|[[:space:]])xl/' "$ZIP_LIST"; then
            type_label="XLSX / Excel OOXML workbook"
            is_xlsx=1
            info "ZIP internals contain xl/ and [Content_Types].xml: likely XLSX."
        elif grep -Eq '(^|[[:space:]])ppt/' "$ZIP_LIST"; then
            type_label="PPTX / PowerPoint OOXML deck"
            is_pptx=1
            info "ZIP internals contain ppt/ and [Content_Types].xml: likely PPTX."
        fi
    fi

    if grep -Eqi 'META-INF/MANIFEST\.MF|\.class$' "$ZIP_LIST"; then
        is_jar=1
        if [ "$is_docx" -eq 0 ] && [ "$is_xlsx" -eq 0 ] && [ "$is_pptx" -eq 0 ]; then
            type_label="JAR / Java archive"
            info "ZIP internals contain Java/JAR indicators."
        fi
    fi
elif [ "$is_zip" -eq 1 ]; then
    warn "unzip not found; ZIP/OOXML inspection skipped."
fi

# ── Extension mismatch checks ───────────────────────────
# Simpel gehouden: alleen opvallende combinaties waarschuwen.
case "$extension:$magic4" in
    jpg:4D5A*|jpeg:4D5A*|png:4D5A*|gif:4D5A*|pdf:4D5A*|txt:4D5A*|docx:4D5A*|xlsx:4D5A*|pptx:4D5A*)
        warn "Extension .$extension, but MZ/Windows executable magic bytes found. Strongly suspicious."
        ;;
    jpg:7F454C46*|jpeg:7F454C46*|png:7F454C46*|gif:7F454C46*|pdf:7F454C46*|txt:7F454C46*|docx:7F454C46*|xlsx:7F454C46*|pptx:7F454C46*)
        warn "Extension .$extension, but ELF executable magic bytes found. Strongly suspicious."
        ;;
    exe:25504446*|dll:25504446*|scr:25504446*)
        warn "Extension .$extension, but PDF magic bytes found. File type may not match."
        ;;
    exe:89504E47*|dll:89504E47*|scr:89504E47*)
        warn "Extension .$extension, but PNG magic bytes found. File type may not match."
        ;;
    exe:FFD8FF*|dll:FFD8FF*|scr:FFD8FF*)
        warn "Extension .$extension, but JPEG magic bytes found. File type may not match."
        ;;
esac

if [ "$is_zip" -eq 1 ]; then
    case "$extension" in
        zip|docx|xlsx|pptx|jar) ;;
        *)
            warn "File looks like ZIP/OOXML/JAR content, but extension is .$extension."
            ;;
    esac
fi

if [ "$is_docx" -eq 1 ] && [ "$extension" != "docx" ] && [ "$extension" != "zip" ]; then
    warn "Internal structure looks like DOCX, but extension is .$extension."
fi

if [ "$is_xlsx" -eq 1 ] && [ "$extension" != "xlsx" ] && [ "$extension" != "zip" ]; then
    warn "Internal structure looks like XLSX, but extension is .$extension."
fi

if [ "$is_pptx" -eq 1 ] && [ "$extension" != "pptx" ] && [ "$extension" != "zip" ]; then
    warn "Internal structure looks like PPTX, but extension is .$extension."
fi

if [ "$is_jar" -eq 1 ] && [ "$extension" != "jar" ] && [ "$extension" != "zip" ]; then
    warn "Internal structure looks like JAR/Java archive, but extension is .$extension."
fi

# ── TEXT/STRINGS ────────────────────────────────────────
section "TEXT/STRINGS"

if [ "$is_text" -eq 1 ]; then
    info "file(1) thinks this is probably text/script data."
    echo "First 40 lines:"
    head -n 40 "$FILE" 2>/dev/null || warn "Could not read text preview."

    if have strings; then
        strings -n 6 "$FILE" > "$STRINGS_FILE" 2>/dev/null || : > "$STRINGS_FILE"
    else
        sed -n '1,500p' "$FILE" > "$STRINGS_FILE" 2>/dev/null || : > "$STRINGS_FILE"
    fi

    maybe_less "$FILE" "text file"
else
    info "file(1) thinks this is probably binary/container data."

    if have strings; then
        strings -n 6 "$FILE" > "$STRINGS_FILE" 2>/dev/null || : > "$STRINGS_FILE"
        echo "First 40 strings (-n 6):"
        if [ -s "$STRINGS_FILE" ]; then
            head -n 40 "$STRINGS_FILE"
        else
            echo "(no strings found)"
        fi
        maybe_less "$STRINGS_FILE" "strings output"
    else
        : > "$STRINGS_FILE"
        warn "strings not found; IOC extraction will be limited."
    fi
fi

# ── IOCS ────────────────────────────────────────────────
section "IOCS"

echo
echo -e "${BOLD}URLs${NC}"
grep -Eaio 'https?://[^[:space:]<>"'"'"')}]+' "$STRINGS_FILE" 2>/dev/null | sort -fu | head -n 20 > "$HITS_FILE" || true
if [ -s "$HITS_FILE" ]; then
    cat "$HITS_FILE"
    ioc_count=$((ioc_count + $(wc -l < "$HITS_FILE" | tr -d ' ')))
else
    echo "(none)"
fi

echo
echo -e "${BOLD}IP addresses${NC}"
grep -Eaio '([0-9]{1,3}\.){3}[0-9]{1,3}' "$STRINGS_FILE" 2>/dev/null | sort -fu | head -n 20 > "$HITS_FILE" || true
if [ -s "$HITS_FILE" ]; then
    cat "$HITS_FILE"
    ioc_count=$((ioc_count + $(wc -l < "$HITS_FILE" | tr -d ' ')))
else
    echo "(none)"
fi

echo
echo -e "${BOLD}Email addresses${NC}"
grep -Eaio '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$STRINGS_FILE" 2>/dev/null | sort -fu | head -n 20 > "$HITS_FILE" || true
if [ -s "$HITS_FILE" ]; then
    cat "$HITS_FILE"
    ioc_count=$((ioc_count + $(wc -l < "$HITS_FILE" | tr -d ' ')))
else
    echo "(none)"
fi

echo
echo -e "${BOLD}Domains${NC}"
grep -Eaio '([A-Za-z0-9-]+\.)+(com|net|org|io|co|be|nl|de|fr|uk|ru|cn|info|biz|top|xyz|site|online|app|dev)' "$STRINGS_FILE" 2>/dev/null | sort -fu | head -n 30 > "$HITS_FILE" || true
if [ -s "$HITS_FILE" ]; then
    cat "$HITS_FILE"
    ioc_count=$((ioc_count + $(wc -l < "$HITS_FILE" | tr -d ' ')))
else
    echo "(none)"
fi

echo
echo -e "${BOLD}Suspicious keywords${NC}"
grep -Eai 'powershell|cmd\.exe|/bin/bash|/bin/sh|/dev/tcp|(^|[^[:alnum:]_])nc([^[:alnum:]_]|$)|curl|wget|base64|(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)|(^|[^[:alnum:]_])exec([^[:alnum:]_]|$)|os\.system|pickle\.loads|password|admin|token|secret' "$STRINGS_FILE" 2>/dev/null | head -n 30 > "$HITS_FILE" || true
if [ -s "$HITS_FILE" ]; then
    cat "$HITS_FILE"
    keyword_count="$(wc -l < "$HITS_FILE" | tr -d ' ')"
    warn "Suspicious keywords found in strings/text."

    if grep -Eai 'powershell|cmd\.exe|/bin/bash|/bin/sh|/dev/tcp|(^|[^[:alnum:]_])nc([^[:alnum:]_]|$)|curl|wget' "$HITS_FILE" >/dev/null 2>&1; then
        score=$((score + 1))
        echo -e "${YELLOW}⚠️  Shell/download/network execution indicators present.${NC}"
    fi

    if grep -Eai 'base64|(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)|(^|[^[:alnum:]_])exec([^[:alnum:]_]|$)|os\.system|pickle\.loads' "$HITS_FILE" >/dev/null 2>&1; then
        score=$((score + 1))
        echo -e "${YELLOW}⚠️  Obfuscation or dynamic execution indicators present.${NC}"
    fi
else
    echo "(none)"
fi

if [ "$ioc_count" -gt 0 ]; then
    warn "Possible network/account IOCs found. Output is limited; inspect full text/strings if needed."
fi

# ── METADATA ────────────────────────────────────────────
section "METADATA"

metadata_shown=0

if [ "$is_zip" -eq 1 ]; then
    echo -e "${BOLD}ZIP contents preview${NC}"
    if [ -s "$ZIP_LIST" ]; then
        head -n 35 "$ZIP_LIST"
    elif have unzip; then
        unzip -l "$FILE" 2>/dev/null | head -n 35
    else
        echo "(unzip not found)"
    fi
    metadata_shown=1

    if [ "$is_docx" -eq 1 ]; then
        echo
        echo -e "${BOLD}DOCX core metadata${NC}"
        if unzip -p "$FILE" docProps/core.xml > "$CORE_XML" 2>/dev/null && [ -s "$CORE_XML" ]; then
            sed \
                -e 's/<[^>]*>/ /g' \
                -e 's/&lt;/</g' \
                -e 's/&gt;/>/g' \
                -e 's/&amp;/\&/g' \
                -e 's/&quot;/"/g' \
                -e "s/&apos;/'/g" \
                -e 's/[[:space:]][[:space:]]*/ /g' \
                -e 's/^ //; s/ $//' "$CORE_XML" \
                | fold -s -w 100 \
                | head -n 20
        else
            echo "(docProps/core.xml not found or unreadable)"
        fi
    fi
fi

if [ "$is_pdf" -eq 1 ]; then
    echo -e "${BOLD}PDF metadata strings${NC}"
    if have strings; then
        strings "$FILE" 2>/dev/null | grep -Ei 'Author|Creator|Producer|CreationDate|ModDate' | head -n 25 || echo "(none)"
    else
        echo "(strings not found)"
    fi
    metadata_shown=1
fi

if have exiftool; then
    echo
    echo -e "${BOLD}exiftool metadata${NC}"
    exiftool "$FILE" 2>/dev/null | head -n 40 || echo "(exiftool failed)"
    metadata_shown=1
elif [ "$is_pdf" -eq 1 ]; then
    echo
    echo "exiftool not found; PDF metadata is limited to strings."
fi

if [ "$metadata_shown" -eq 0 ]; then
    echo "(no ZIP/OOXML/PDF metadata path applicable)"
fi

# ── SCORE ───────────────────────────────────────────────
section "SCORE"

echo "Detected type: $type_label"
echo "Warnings: $warn_count"
echo "IOC hits shown: $ioc_count"
echo "Keyword hits shown: $keyword_count"
echo

if [ "$score" -eq 0 ]; then
    echo -e "${GREEN}Score: $score — geen duidelijke signalen in deze snelle static triage.${NC}"
elif [ "$score" -le 2 ]; then
    echo -e "${YELLOW}Score: $score — verder bekijken; er zijn lichte of context-afhankelijke signalen.${NC}"
else
    echo -e "${RED}Score: $score — verdacht genoeg voor analyse in VM/sandbox. Niet uitvoeren op je host.${NC}"
fi
