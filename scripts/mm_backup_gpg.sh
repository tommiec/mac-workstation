#!/bin/bash
# =========================================================
# mm_backup_gpg.sh
# Back up GPG private keys, public keys, ownertrust and ~/.gnupg
# into gpg-backup/ inside the encrypted iCloud sparsebundle.
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mm_common.sh"

GPG_SOURCE="${GNUPGHOME:-$HOME/.gnupg}"
STAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
TMP_BACKUP=""

echo "── 🔏 GPG backup ──"
echo
echo "Vault: $VAULT_PATH"
echo "Source: $GPG_SOURCE"
echo

if [[ ! -d "$GPG_SOURCE" ]]; then
    echo "❌ GPG home folder not found: $GPG_SOURCE"
    exit 1
fi

for tool in diskutil hdiutil rsync gpg tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Required tool not found: $tool"
        exit 1
    fi
done

if ! ensure_vault; then
    echo "❌ Could not create encrypted sparsebundle"
    exit 1
fi

cleanup() {
    local status="$1"
    if [[ -n "$TMP_BACKUP" && -d "$TMP_BACKUP" ]]; then
        rm -rf "$TMP_BACKUP"
    fi
    vault_eject
    record_script_result "mm_backup_gpg.sh" "$status"
}
trap 'status=$?; cleanup "$status"' EXIT

if ! vault_mount; then
    echo "❌ Could not mount encrypted sparsebundle"
    exit 1
fi

TMP_BACKUP="$(mktemp -d "${TMPDIR:-/tmp}/mm_gpg_backup.XXXXXX")" || {
    echo "❌ Could not create temporary backup folder"
    exit 1
}
chmod 700 "$TMP_BACKUP" 2>/dev/null || true

PORTABLE_DIR="$TMP_BACKUP/portable"
FULL_DIR="$TMP_BACKUP/full-gnupg"
mkdir -p "$PORTABLE_DIR" "$FULL_DIR"

if command -v gpgconf >/dev/null 2>&1; then
    echo "Restarting GPG agent..."
    gpgconf --kill all >/dev/null 2>&1 || true
fi

echo "Listing secret keys..."
if ! gpg --list-secret-keys --keyid-format LONG > "$PORTABLE_DIR/secret-keys-list.txt"; then
    echo "❌ Could not list GPG secret keys"
    exit 1
fi

SECRET_KEY_COUNT="$(grep -c '^sec ' "$PORTABLE_DIR/secret-keys-list.txt" 2>/dev/null || true)"
SECRET_KEY_COUNT="${SECRET_KEY_COUNT:-0}"

echo "Exporting public keys..."
if ! gpg --export --armor > "$PORTABLE_DIR/public-keys.asc"; then
    echo "❌ Could not export public GPG keys"
    exit 1
fi

if [[ "$SECRET_KEY_COUNT" -gt 0 ]]; then
    echo "Exporting secret keys..."
    if ! gpg --export-secret-keys --armor > "$PORTABLE_DIR/secret-keys.asc"; then
        echo "❌ Could not export secret GPG keys"
        exit 1
    fi
else
    echo "No secret keys found; writing empty secret-keys.asc"
    : > "$PORTABLE_DIR/secret-keys.asc"
fi

echo "Exporting ownertrust..."
if ! gpg --export-ownertrust > "$PORTABLE_DIR/ownertrust.txt"; then
    echo "❌ Could not export GPG ownertrust"
    exit 1
fi

echo "Copying ~/.gnupg..."
mkdir -p "$FULL_DIR/.gnupg"
if ! rsync -rltpgo --delete \
    --exclude 'S.*' \
    --exclude '*.lock' \
    "$GPG_SOURCE/" "$FULL_DIR/.gnupg/"; then
    echo "❌ Could not copy GPG home folder"
    exit 1
fi

cat > "$TMP_BACKUP/manifest.txt" <<EOF
source=$GPG_SOURCE
created_at=$(date '+%Y-%m-%d %H:%M:%S %z')
vault=$VAULT_PATH
secret_key_count=$SECRET_KEY_COUNT
portable_exports=public-keys.asc, secret-keys.asc, ownertrust.txt, secret-keys-list.txt
full_copy=full-gnupg/.gnupg
excluded=S.*, *.lock
restore_public=gpg --import public-keys.asc
restore_secret=gpg --import secret-keys.asc
restore_ownertrust=gpg --import-ownertrust ownertrust.txt
EOF

BACKUP_ROOT="$VAULT_MOUNT_POINT/gpg-backup"
LATEST_DIR="$BACKUP_ROOT/latest"
ARCHIVE_DIR="$BACKUP_ROOT/archives"
ARCHIVE_PATH="$ARCHIVE_DIR/gpg-backup-$STAMP.tar.gz"
mkdir -p "$LATEST_DIR" "$ARCHIVE_DIR"

echo "Writing backup to vault..."
if ! rsync -a --delete "$PORTABLE_DIR/" "$LATEST_DIR/portable/"; then
    echo "❌ Could not write portable GPG exports"
    exit 1
fi
if ! rsync -a --delete "$FULL_DIR/" "$LATEST_DIR/full-gnupg/"; then
    echo "❌ Could not write full GPG backup"
    exit 1
fi
cp "$TMP_BACKUP/manifest.txt" "$LATEST_DIR/manifest.txt" || {
    echo "❌ Could not write GPG backup manifest"
    exit 1
}

if ! tar -czf "$ARCHIVE_PATH" -C "$TMP_BACKUP" portable full-gnupg manifest.txt; then
    echo "❌ Could not create GPG backup archive"
    exit 1
fi

PORTABLE_FILE_COUNT="$(find "$LATEST_DIR/portable" -type f 2>/dev/null | wc -l | tr -d ' ')"
FULL_FILE_COUNT="$(find "$LATEST_DIR/full-gnupg/.gnupg" -type f 2>/dev/null | wc -l | tr -d ' ')"

LOCAL_SECRET_EXPORT="$HOME/secret-keys.asc"
if [[ -f "$LOCAL_SECRET_EXPORT" ]] && grep -q "BEGIN PGP PRIVATE KEY BLOCK" "$LOCAL_SECRET_EXPORT" 2>/dev/null; then
    echo
    echo "Plain-text GPG secret key export found: $LOCAL_SECRET_EXPORT"
    echo "The encrypted vault backup succeeded, so this local copy should be removed."
    rm -i "$LOCAL_SECRET_EXPORT"
fi

echo
echo "✅ GPG backup complete"
echo "   Secret keys: $SECRET_KEY_COUNT"
echo "   Portable files: $PORTABLE_FILE_COUNT"
echo "   Full .gnupg files: $FULL_FILE_COUNT"
echo "   Latest backup: $LATEST_DIR"
echo "   Archive: $ARCHIVE_PATH"
echo
if [[ "$VAULT_MOUNTED_BY_SCRIPT" -eq 1 ]]; then
    echo "The vault will now be unmounted. Wait for iCloud Drive to finish syncing it."
else
    echo "The vault was already mounted, so it will stay open."
fi
