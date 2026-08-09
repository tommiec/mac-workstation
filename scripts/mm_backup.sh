#!/bin/bash
# =========================================================
# mm_backup.sh
# Back up SSH, GPG material and the git profile in one vault session.
#
# Usage:
#   mm backup                         # back up every supported section
#   mm backup --ssh                   # SSH only
#   mm backup --gpg                   # GPG only
#   mm backup --git-profile           # git profile only
#
# The individual mm_backup_*.sh scripts remain usable on their own. This
# command mounts the encrypted vault once, passes that mount to each selected
# script, and ejects it once all selected sections have finished.
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mm_common.sh"

DO_SSH=0
DO_GPG=0
DO_GIT_PROFILE=0
BACKUP_FAILED=0

usage() {
    cat <<'EOF'
Usage: mm backup [--ssh] [--gpg] [--git-profile]

  (no flags)     Back up SSH, GPG and the git profile in one vault session.
  --ssh          Back up SSH material only.
  --gpg          Back up GPG material only.
  --git-profile  Back up the git commit identity only.
  -h, --help     Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh) DO_SSH=1 ;;
        --gpg) DO_GPG=1 ;;
        --git-profile) DO_GIT_PROFILE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; echo; usage; exit 1 ;;
    esac
    shift
done

if [[ "$DO_SSH" -eq 0 && "$DO_GPG" -eq 0 && "$DO_GIT_PROFILE" -eq 0 ]]; then
    DO_SSH=1
    DO_GPG=1
    DO_GIT_PROFILE=1
fi

cleanup() {
    local status="$1"
    vault_eject
    record_script_result "mm_backup.sh" "$status"
}
trap 'status=$?; cleanup "$status"' EXIT

echo "── 🔐 Secrets backup ──"
echo
echo "Vault: $VAULT_PATH"
echo "The vault is mounted once for all selected backup sections."
echo

if ! ensure_vault; then
    echo "❌ Could not create encrypted sparsebundle"
    exit 1
fi

if ! vault_mount; then
    echo "❌ Could not mount encrypted sparsebundle"
    exit 1
fi

run_backup() {
    local label="$1"
    local script="$2"

    if MM_VAULT_MOUNT_POINT="$VAULT_MOUNT_POINT" bash "$SCRIPT_DIR/$script"; then
        log_ok "$label backup completed"
    else
        log_warn "$label backup failed"
        BACKUP_FAILED=1
    fi
}

[[ "$DO_SSH" -eq 1 ]] && run_backup "SSH" "mm_backup_ssh.sh"
[[ "$DO_GPG" -eq 1 ]] && run_backup "GPG" "mm_backup_gpg.sh"
[[ "$DO_GIT_PROFILE" -eq 1 ]] && run_backup "Git profile" "mm_backup_git.sh"

echo
echo "── 📊 Backup summary ─────────────────────────────"
if [[ "$BACKUP_FAILED" -eq 0 ]]; then
    echo "✅ All selected backups completed"
else
    echo "❌ One or more selected backups failed; see the warnings above."
fi

if [[ "$VAULT_MOUNTED_BY_SCRIPT" -eq 1 ]]; then
    echo "   The vault will now be unmounted. Wait for iCloud Drive to finish syncing it."
else
    echo "   The vault was already mounted, so it will stay open."
fi

exit "$BACKUP_FAILED"
