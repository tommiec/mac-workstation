#!/bin/bash
# =========================================================
# mm_backup_git.sh
# Mirror ~/.config/git/git-profile.conf into git-profile/ inside the encrypted
# iCloud sparsebundle.
#
# Deliberately its own script rather than a step inside the SSH or GPG backup:
# those abort early when ~/.ssh or a keyring is absent, which on a machine
# without SSH keys would silently mean the git identity never reaches the vault
# at all. The commit identity must not depend on unrelated material existing.
#
# The file holds the commit identity and the forge URLs — personal data and
# internal network topology — which is why it lives outside the public
# mac-workstation repository and only ever leaves this machine encrypted.
# Counterpart: 'mm restore --git-profile'. Policy: ~/Repositories/GIT.md
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mm_common.sh"

echo "── 🪪  Git profile backup ──"
echo
echo "Vault: $VAULT_PATH"
echo "Source: $GIT_PROFILE_CONF"
echo

if [[ ! -f "$GIT_PROFILE_CONF" ]]; then
    echo "❌ No git profile to back up: $GIT_PROFILE_CONF"
    echo "   Create it from configs/git-profile.conf.example, or restore it with"
    echo "   'mm restore --git-profile --apply'."
    exit 1
fi

for tool in diskutil shasum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Required tool not found: $tool"
        exit 1
    fi
done

if ! ensure_vault; then
    echo "❌ Could not create encrypted sparsebundle"
    exit 1
fi

trap 'finish_vault_run "mm_backup_git.sh" "$?"' EXIT

if ! vault_mount; then
    echo "❌ Could not mount encrypted sparsebundle"
    exit 1
fi

if ! backup_git_profile; then
    echo "❌ Could not write the git profile to the vault"
    exit 1
fi

BACKUP_FILE="$VAULT_MOUNT_POINT/git-profile/git-profile.conf"

echo "Verifying Git profile backup checksum..."
if ! verify_backup "$GIT_PROFILE_CONF" "$BACKUP_FILE"; then
    echo "❌ Git profile backup verification failed"
    exit 1
fi

cat > "$VAULT_MOUNT_POINT/git-profile/manifest.txt" <<EOF
source=$GIT_PROFILE_CONF
created_at=$(date '+%Y-%m-%d %H:%M:%S %z')
vault=$VAULT_PATH
restore=mm restore --git-profile --apply, then mm install
note=forge credentials live in the Keychain and are deliberately not backed up
EOF

echo "✅ Git profile backup complete"
echo "   Checksum: verified"
echo "   Backup: $BACKUP_FILE"
echo "   Forges: $(git_profile_forges | tr '\n' ' ')"
echo
echo "   Restoring this file is only half the job: 'mm install' turns it into"
echo "   the identity files and includeIf rules."
echo
if [[ "$VAULT_MOUNTED_BY_SCRIPT" -eq 1 ]]; then
    echo "The vault will now be unmounted. Wait for iCloud Drive to finish syncing it."
else
    echo "The vault was already mounted, so it will stay open."
fi
