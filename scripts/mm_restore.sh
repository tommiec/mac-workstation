#!/bin/bash
# =========================================================
# mm_restore.sh
# Restore SSH material, GPG material and the git commit
# identity from the encrypted iCloud sparsebundle onto a
# freshly installed Mac.
#
# Usage (after installation):
#   mm restore                  # dry run: show what would happen, change nothing
#   mm restore --apply          # actually restore every section
#   mm restore --ssh --apply    # restore SSH only
#   mm restore --gpg --apply    # restore GPG only
#   mm restore --git-profile --apply
#                               # restore the commit identity only; follow with
#                               # 'mm install' to regenerate the identity files
#   mm restore --gpg --full-gnupg --apply
#                               # replace ~/.gnupg wholesale instead of
#                               # importing the portable exports
#
# What this script does:
#   - Mounts the existing vault (macOS asks for the password; the script
#     never reads, stores or logs it) and never creates a new one
#   - Copies ssh-backup/.ssh into ~/.ssh and hardens the permissions
#   - Imports the portable GPG exports (public keys, secret keys, ownertrust)
#     INTO the existing keyring; use --full-gnupg to replace it instead
#   - Copies git-profile/git-profile.conf into ~/.config/git; 'mm install' then
#     turns it into the identity files and includeIf rules
#   - Moves anything it would overwrite aside instead of deleting it
#   - Never prints key material and never touches pem-archive/
#
# Forge credentials live in the Keychain and are deliberately NOT in the vault,
# so pushing asks you to authenticate again after a restore.
#
# This is the counterpart of mm_backup_ssh.sh, mm_backup_gpg.sh and
# mm_backup_git.sh.
# =========================================================

set -o pipefail
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mm_common.sh"

STAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
SSH_TARGET="$HOME/.ssh"
GPG_TARGET="${GNUPGHOME:-$HOME/.gnupg}"

DRY_RUN=1
DO_SSH=0
DO_GPG=0
DO_GIT_PROFILE=0
FULL_GNUPG=0

usage() {
    cat <<'EOF'
Usage: mm restore [--ssh] [--gpg] [--git-profile] [--full-gnupg] [--apply]

  (no flags)     Dry run of every section. Writes nothing to ~/.ssh, ~/.gnupg
                 or ~/.config/git.
  --ssh          Restore SSH only.
  --gpg          Restore GPG only.
  --git-profile  Restore the commit identity and forge routing only.
  --full-gnupg   With --gpg: replace ~/.gnupg with the full backup copy
                 instead of importing the portable exports.
  --apply        Perform the restore. Without this everything is a dry run.
  -h, --help     Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh) DO_SSH=1 ;;
        --gpg) DO_GPG=1 ;;
        --git-profile) DO_GIT_PROFILE=1 ;;
        --full-gnupg) FULL_GNUPG=1 ;;
        --apply) DRY_RUN=0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; echo; usage; exit 1 ;;
    esac
    shift
done

# No section flags means every section.
if [[ "$DO_SSH" -eq 0 && "$DO_GPG" -eq 0 && "$DO_GIT_PROFILE" -eq 0 ]]; then
    DO_SSH=1
    DO_GPG=1
    DO_GIT_PROFILE=1
fi

if [[ "$FULL_GNUPG" -eq 1 && "$DO_GPG" -eq 0 ]]; then
    echo "❌ --full-gnupg only applies together with --gpg"
    exit 1
fi

echo "── ♻️  Secrets restore ──"
echo
echo "Vault: $VAULT_PATH"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Mode:  DRY RUN — nothing is written to ~/.ssh or ~/.gnupg."
    echo "       The vault is still mounted and a run status is still recorded."
    echo "       Re-run with --apply to restore."
else
    echo "Mode:  APPLY — files will be written."
fi
echo

# ── Preflight ───────────────────────────────────────────
# ensure_vault() from mm_common.sh would CREATE a blank vault when none
# exists. On a restore an absent vault means the backup is missing, so bail
# out loudly rather than silently producing an empty one.
if [[ ! -e "$VAULT_PATH" ]]; then
    echo "❌ No vault found at: $VAULT_PATH"
    echo "   Restore needs an existing backup. If the vault lives in iCloud,"
    echo "   open iCloud Drive and let it finish downloading first."
    exit 1
fi

for tool in diskutil hdiutil rsync; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Required tool not found: $tool"
        exit 1
    fi
done

if [[ "$DO_GPG" -eq 1 ]] && ! command -v gpg >/dev/null 2>&1; then
    echo "❌ Required tool not found: gpg (install GPG Suite via 'mm install')"
    exit 1
fi

# Invoked from the EXIT trap below; shellcheck cannot see through the quoted
# trap body.
# shellcheck disable=SC2329
cleanup() {
    local status="$1"
    vault_eject
    record_script_result "mm_restore.sh" "$status"
}
trap 'status=$?; cleanup "$status"' EXIT

if ! vault_mount; then
    echo "❌ Could not mount the vault"
    echo "   macOS asks for the vault password; cancelling the dialog aborts the restore."
    exit 1
fi

# Moves an existing target aside instead of overwriting it. Never deletes.
preserve_existing() {
    local target="$1"
    local kept="$target.pre-restore-$STAMP"

    [[ -e "$target" ]] || return 0
    if [[ -d "$target" ]] && [[ -z "$(ls -A "$target" 2>/dev/null)" ]]; then
        return 0
    fi

    # Refuse rather than risk 'mv' nesting the target inside an existing
    # directory of the same name after a timestamp collision.
    if [[ -e "$kept" ]]; then
        log_warn "Refusing to move $target aside: $kept already exists"
        return 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "Would move existing $target aside to $kept"
        return 0
    fi
    mv "$target" "$kept" || return 1
    log_info "Existing $target moved aside to $kept"
}

# ── SSH ─────────────────────────────────────────────────
restore_ssh() {
    local backup_dir="$VAULT_MOUNT_POINT/ssh-backup/.ssh"
    local manifest="$VAULT_MOUNT_POINT/ssh-backup/manifest.txt"
    local file_count=0
    local rsync_flags=(-a)

    echo
    echo "── 🔐 SSH ────────────────────────────────────────"

    if [[ ! -d "$backup_dir" ]]; then
        log_warn "No SSH backup in the vault: $backup_dir"
        return 1
    fi

    file_count="$(find "$backup_dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$file_count" -eq 0 ]]; then
        log_warn "SSH backup folder is empty; nothing to restore"
        return 1
    fi

    if [[ -f "$manifest" ]]; then
        # Shows the age of the backup so an accidental restore from a stale
        # vault is visible before anything is written.
        log_info "Backup taken: $(sed -n 's/^created_at=//p' "$manifest")"
    fi
    log_info "Files in backup: $file_count"

    preserve_existing "$SSH_TARGET" || return 1

    [[ "$DRY_RUN" -eq 1 ]] && rsync_flags+=(--dry-run --itemize-changes)
    if ! rsync "${rsync_flags[@]}" "$backup_dir/" "$SSH_TARGET/"; then
        log_warn "SSH restore failed"
        return 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "Would harden permissions: 700 on $SSH_TARGET, 600 on private keys"
        log_ok "SSH restore looks ready ($file_count files)"
        return 0
    fi

    harden_ssh_permissions || return 1
    log_ok "SSH restored to $SSH_TARGET ($file_count files)"
}

# OpenSSH refuses to use a key whose permissions are too open, and the vault
# is not guaranteed to preserve modes across filesystems, so set them here.
harden_ssh_permissions() {
    chmod 700 "$SSH_TARGET" || return 1
    find "$SSH_TARGET" -type d -exec chmod 700 {} + 2>/dev/null || true
    find "$SSH_TARGET" -type f -exec chmod 600 {} + 2>/dev/null || true
    # Public material may stay world-readable; keeps ssh-copy-id and tooling happy.
    find "$SSH_TARGET" -type f \( -name '*.pub' -o -name 'known_hosts*' \) \
        -exec chmod 644 {} + 2>/dev/null || true
}

# ── GPG ─────────────────────────────────────────────────
restore_gpg() {
    local portable="$VAULT_MOUNT_POINT/gpg-backup/latest/portable"
    local manifest="$VAULT_MOUNT_POINT/gpg-backup/latest/manifest.txt"

    echo
    echo "── 🔏 GPG ────────────────────────────────────────"

    if [[ "$FULL_GNUPG" -eq 1 ]]; then
        restore_gpg_full
        return $?
    fi

    if [[ ! -d "$portable" ]]; then
        log_warn "No portable GPG backup in the vault: $portable"
        return 1
    fi

    if [[ -f "$manifest" ]]; then
        log_info "Backup taken: $(sed -n 's/^created_at=//p' "$manifest")"
        log_info "Secret keys in backup: $(sed -n 's/^secret_key_count=//p' "$manifest")"
    fi

    # Unlike the SSH and --full-gnupg paths, this imports INTO the existing
    # keyring instead of replacing it: keys already present survive, and
    # ownertrust values for keys in the backup are overwritten. Snapshot the
    # current trust database first so that overwrite stays reversible.
    log_info "Portable import merges into the existing keyring; it does not replace it"
    snapshot_ownertrust || return 1

    import_gpg_file "$portable/public-keys.asc" "public keys" --import || return 1
    import_gpg_file "$portable/secret-keys.asc" "secret keys" --import || return 1
    import_gpg_file "$portable/ownertrust.txt" "ownertrust" --import-ownertrust || return 1

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_ok "GPG import looks ready"
        return 0
    fi

    log_ok "GPG material imported into $GPG_TARGET"
}

# Saves the current ownertrust next to the keyring before the backup's trust
# values are imported over it. Trust records are not key material.
snapshot_ownertrust() {
    local snapshot="$GPG_TARGET/ownertrust.pre-restore-$STAMP.txt"

    [[ -d "$GPG_TARGET" ]] || return 0
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "Would save current ownertrust to $(basename "$snapshot")"
        return 0
    fi
    if gpg --export-ownertrust > "$snapshot" 2>/dev/null; then
        log_info "Current ownertrust saved to $(basename "$snapshot")"
    else
        log_warn "Could not save current ownertrust before importing"
        return 1
    fi
}

# Imports one exported file. Key material is never echoed: only the file name,
# its size and the gpg exit status are reported.
import_gpg_file() {
    local file="$1"
    local label="$2"
    local gpg_flag="$3"

    # The backup script always writes all three exports, so a missing one
    # means the backup itself is incomplete rather than merely empty.
    if [[ ! -f "$file" ]]; then
        log_warn "Missing $label export: $(basename "$file")"
        return 1
    fi
    if [[ ! -s "$file" ]]; then
        log_info "Skipping $label: export is empty"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "Would run: gpg $gpg_flag $(basename "$file")"
        return 0
    fi

    # gpg may open a pinentry dialog for the secret key passphrase; that
    # exchange stays between GPG and the user.
    if gpg --batch "$gpg_flag" "$file" >/dev/null 2>&1; then
        log_ok "Imported $label"
    else
        log_warn "Could not import $label from $(basename "$file")"
        return 1
    fi
}

restore_gpg_full() {
    local full="$VAULT_MOUNT_POINT/gpg-backup/latest/full-gnupg/.gnupg"
    local rsync_flags=(-rltpgo)

    if [[ ! -d "$full" ]]; then
        log_warn "No full .gnupg backup in the vault: $full"
        return 1
    fi

    log_info "Replacing $GPG_TARGET with the full backup copy"
    if [[ "$DRY_RUN" -eq 0 ]] && command -v gpgconf >/dev/null 2>&1; then
        # Sockets must be gone before the folder is swapped, or the running
        # agent keeps writing into the old directory.
        gpgconf --kill all >/dev/null 2>&1 || true
    fi

    preserve_existing "$GPG_TARGET" || return 1

    [[ "$DRY_RUN" -eq 1 ]] && rsync_flags+=(--dry-run --itemize-changes)
    if ! rsync "${rsync_flags[@]}" --exclude 'S.*' --exclude '*.lock' \
        "$full/" "$GPG_TARGET/"; then
        log_warn "Full GPG restore failed"
        return 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "Would set 700 on $GPG_TARGET and 600 on its files"
        log_ok "Full GPG restore looks ready"
        return 0
    fi

    chmod 700 "$GPG_TARGET" || return 1
    find "$GPG_TARGET" -type d -exec chmod 700 {} + 2>/dev/null || true
    find "$GPG_TARGET" -type f -exec chmod 600 {} + 2>/dev/null || true
    log_ok "Full .gnupg restored to $GPG_TARGET"
}

# ── Git profile ─────────────────────────────────────────
# Holds the commit identity and the forge URLs. Restoring the file is only half
# the job: 'mm install' turns it into the identity-* files and the includeIf
# rules, so the reminder below is part of the restore, not an afterthought.
restore_git_profile() {
    local backup="$VAULT_MOUNT_POINT/git-profile/git-profile.conf"

    echo
    echo "── 🪪  Git profile ────────────────────────────────"

    if [[ ! -f "$backup" ]]; then
        log_warn "No git profile in the vault: $backup"
        return 1
    fi

    if [[ -f "$GIT_PROFILE_CONF" ]] && cmp -s "$backup" "$GIT_PROFILE_CONF"; then
        log_ok "Git profile already matches the vault copy: $GIT_PROFILE_CONF"
        return 0
    fi

    preserve_existing "$GIT_PROFILE_CONF" || return 1

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "Would restore $backup to $GIT_PROFILE_CONF"
        log_info "Would then need 'mm install' to regenerate the identity files"
        log_ok "Git profile restore looks ready"
        return 0
    fi

    mkdir -p "$(dirname "$GIT_PROFILE_CONF")" || return 1
    cp "$backup" "$GIT_PROFILE_CONF" || return 1
    chmod 600 "$GIT_PROFILE_CONF" || return 1
    log_ok "Git profile restored to $GIT_PROFILE_CONF"
    log_info "Run 'mm install' to regenerate ~/.config/git/identity-* and the includeIf rules"
}

# ── Run ─────────────────────────────────────────────────
RESTORE_FAILED=0
if [[ "$DO_SSH" -eq 1 ]]; then
    restore_ssh || RESTORE_FAILED=1
fi
if [[ "$DO_GPG" -eq 1 ]]; then
    restore_gpg || RESTORE_FAILED=1
fi
if [[ "$DO_GIT_PROFILE" -eq 1 ]]; then
    restore_git_profile || RESTORE_FAILED=1
fi

# pem-archive is manual storage that the backup scripts never sync. Report it
# so its contents are not mistaken for something this restore handled.
if [[ -d "$VAULT_MOUNT_POINT/pem-archive" ]]; then
    pem_count="$(find "$VAULT_MOUNT_POINT/pem-archive" -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$pem_count" -gt 0 ]]; then
        echo
        log_info "pem-archive/ holds $pem_count file(s); restore those by hand if needed"
    fi
fi

summary_print
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "   Dry run only. Re-run with --apply to perform the restore."
else
    echo "   Verify with:"
    # Deliberately not 'ssh -T git@github.com': the git remotes here are HTTPS,
    # so that would test an authentication path this machine does not use and
    # fail for the wrong reason. Check the agent instead, and test whichever
    # endpoint the restored key is actually for.
    [[ "$DO_SSH" -eq 1 ]] && echo "     ssh-add -l    # then test your own SSH endpoints"
    [[ "$DO_GPG" -eq 1 ]] && echo "     gpg --list-secret-keys --keyid-format LONG"
    echo "     mm doctor"
fi
echo

if [[ "$RESTORE_FAILED" -ne 0 ]]; then
    echo "   ❌ One or more restore steps failed; see the warnings above."
    echo
fi

# The identity itself now comes from the vault, but the generated identity files
# and includeIf rules do not: those are 'mm install' output. Flag that gap so a
# restored machine does not look finished while every commit still fails.
if [[ "$DO_GIT_PROFILE" -eq 1 && "$DRY_RUN" -eq 0 ]] \
    && [[ ! -f "${LOCAL_GIT_IDENTITY_PREFIX}-github" ]]; then
    log_info "No identity files yet; run 'mm install' to generate them from the profile"
fi

# Signing keys are not part of the profile: signing is opt-in per machine.
if [[ -n "$(git config --global --get commit.gpgsign)" ]] \
    && [[ -z "$(git config --global --get user.signingkey)" ]]; then
    log_warn "commit.gpgsign is on but user.signingkey is unset; commits will fail"
fi

# A failed restore must not be recorded as success by the EXIT trap, or
# 'mm doctor' reports a healthy last run for a machine that has no keys.
exit "$RESTORE_FAILED"
