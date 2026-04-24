#!/bin/bash
# =========================================================
# mac_triage.sh
# Snelle malware/file triage met hash, VirusTotal en strings
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

echo "── 🔎 File triage ──"
echo

echo "== Bestand =="
file "$FILE"
echo

echo "== SHA256 =="
HASH=$(shasum -a 256 "$FILE" | awk '{print $1}')
echo "$HASH"
echo

echo "== VirusTotal lookup =="
if command -v vt >/dev/null 2>&1; then
    vt file "$HASH" || echo "⚠️ Geen resultaat of lookup mislukt."
else
    echo "⚠️ vt CLI niet gevonden."
fi
echo

echo "== Strings =="
echo "Druk op q om te stoppen."
strings "$FILE" | less