#!/bin/bash
# =========================================================
# mm_backup_ssh.sh
# Backup ~/.ssh into an encrypted iCloud sparsebundle
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mm_common.sh"

VAULT_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Secure Vault/Secrets.sparsebundle"
VAULT_NAME="Secrets"
VAULT_SIZE="2g"
SSH_SOURCE="$HOME/.ssh"

echo "── 🔐 SSH backup ──"
echo
echo "Vault: $VAULT_PATH"
echo "Source: $SSH_SOURCE"
echo

if [[ ! -d "$SSH_SOURCE" ]]; then
    echo "❌ ~/.ssh folder not found"
    exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1; then
    echo "❌ Required macOS tools not found: hdiutil and rsync"
    exit 1
fi

mkdir -p "$(dirname "$VAULT_PATH")"

if [[ ! -e "$VAULT_PATH" ]]; then
    echo "Creating encrypted sparsebundle..."
    echo "Choose a strong password and store it in your password manager."
    echo
    if ! hdiutil create \
        -type SPARSEBUNDLE \
        -size "$VAULT_SIZE" \
        -fs APFS \
        -volname "$VAULT_NAME" \
        -encryption AES-256 \
        "$VAULT_PATH"; then
        echo "❌ Could not create encrypted sparsebundle"
        exit 1
    fi
    echo
fi

MOUNT_POINT=""
MOUNTED_BY_SCRIPT=0
find_mounted_vault() {
    hdiutil info 2>/dev/null | awk -v image="$VAULT_PATH" '
        /^[[:space:]]*image-path[[:space:]]*:/ {
            current = $0
            sub(/^[^:]*:[[:space:]]*/, "", current)
        }
        current == image && /^[[:space:]]*mount-point[[:space:]]*:/ {
            mount = $0
            sub(/^[^:]*:[[:space:]]*/, "", mount)
            print mount
            exit
        }
    '
}

cleanup() {
    local status="$1"

    if [[ "$MOUNTED_BY_SCRIPT" -eq 1 && -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi

    record_script_result "mm_backup_ssh.sh" "$status"
}
trap 'status=$?; cleanup "$status"' EXIT

MOUNT_POINT="$(find_mounted_vault)"
if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    echo "Using already mounted vault: $MOUNT_POINT"
else
    echo "Mounting vault..."
    if ! hdiutil attach "$VAULT_PATH" -nobrowse -quiet; then
        echo "❌ Could not mount encrypted sparsebundle"
        exit 1
    fi

    MOUNTED_BY_SCRIPT=1
    MOUNT_POINT="$(find_mounted_vault)"
fi

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
    echo "❌ Could not determine vault mount point"
    exit 1
fi

BACKUP_ROOT="$MOUNT_POINT/Secrets/ssh-backup"
PEM_ARCHIVE="$MOUNT_POINT/Secrets/pem-archive"
mkdir -p "$BACKUP_ROOT" "$PEM_ARCHIVE"

echo "Syncing ~/.ssh..."
if rsync -a --delete \
    --exclude 'agent/' \
    --exclude '*.sock' \
    --exclude 'control-*' \
    "$SSH_SOURCE/" "$BACKUP_ROOT/.ssh/"; then
    chmod 700 "$BACKUP_ROOT/.ssh" 2>/dev/null || true
else
    echo "❌ SSH backup failed"
    exit 1
fi

cat > "$BACKUP_ROOT/manifest.txt" <<EOF
source=$SSH_SOURCE
created_at=$(date '+%Y-%m-%d %H:%M:%S %z')
vault=$VAULT_PATH
excluded=agent/, *.sock, control-*
EOF

SSH_FILE_COUNT="$(find "$BACKUP_ROOT/.ssh" -type f 2>/dev/null | wc -l | tr -d ' ')"

echo
echo "✅ SSH backup complete"
echo "   Files: $SSH_FILE_COUNT"
echo "   Backup: $BACKUP_ROOT/.ssh"
echo "   PEM archive folder kept separate: $PEM_ARCHIVE"
echo
if [[ "$MOUNTED_BY_SCRIPT" -eq 1 ]]; then
    echo "The vault will now be unmounted. Wait for iCloud Drive to finish syncing it."
else
    echo "The vault was already mounted, so it will stay open."
fi
