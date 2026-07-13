#!/bin/bash
# =========================================================
# mm_backup_ssh.sh
# Mirror ~/.ssh into ssh-backup/ inside an encrypted iCloud sparsebundle.
# Creates pem-archive/ as a separate manual area, but never syncs it.
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mm_common.sh"

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

if ! command -v diskutil >/dev/null 2>&1 || ! command -v hdiutil >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1; then
    echo "❌ Required macOS tools not found: diskutil, hdiutil, and rsync"
    exit 1
fi

if ! ensure_vault; then
    echo "❌ Could not create encrypted sparsebundle"
    exit 1
fi

cleanup() {
    local status="$1"
    vault_eject
    record_script_result "mm_backup_ssh.sh" "$status"
}
trap 'status=$?; cleanup "$status"' EXIT

if ! vault_mount; then
    echo "❌ Could not mount encrypted sparsebundle"
    exit 1
fi

BACKUP_ROOT="$VAULT_MOUNT_POINT/ssh-backup"
PEM_ARCHIVE="$VAULT_MOUNT_POINT/pem-archive"
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
if [[ "$VAULT_MOUNTED_BY_SCRIPT" -eq 1 ]]; then
    echo "The vault will now be unmounted. Wait for iCloud Drive to finish syncing it."
else
    echo "The vault was already mounted, so it will stay open."
fi
