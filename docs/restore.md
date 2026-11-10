# Restore on a new Mac

The encrypted iCloud vault contains SSH, GPG and Git identity backups. Restore
them in this order.

## 1. Download the vault

Wait until iCloud Drive has fully downloaded `Secure Vault`. A placeholder
sparsebundle cannot be mounted. Check for remaining placeholders with:

```bash
find ~/Library/Mobile\ Documents/com~apple~CloudDocs/Secure\ Vault -name '*.icloud'
```

## 2. Install Mac Manager

```bash
mkdir -p ~/Repositories/dev
git clone https://github.com/tommiec/mac-workstation.git ~/Repositories/dev/mac-workstation
bash ~/Repositories/dev/mac-workstation/scripts/mm_install.sh
```

A missing Git profile warning is expected: the profile is restored in step 4.
Until step 5 regenerates the identity files, Git deliberately refuses commits.

For an urgent SSH-only restore, skip the full install:

```bash
bash ~/Repositories/dev/mac-workstation/scripts/mm_restore.sh --ssh
bash ~/Repositories/dev/mac-workstation/scripts/mm_restore.sh --ssh --apply
```

## 3. Preview

```bash
mm restore
```

The default is a dry run. It mounts the vault and lists changes without writing
to `~/.ssh`, `~/.gnupg` or `~/.config/git`.

Use `--ssh`, `--gpg` or `--git-profile` to select one section.

## 4. Apply

```bash
mm restore --apply
```

macOS requests the vault password; the script never receives or logs it.

- An existing `~/.ssh` is moved to `~/.ssh.pre-restore-<timestamp>` before the
  restored copy is written and permissions are hardened.
- GPG defaults to importing portable keys and ownertrust into the existing
  keyring. Existing ownertrust is exported first.
- `mm restore --gpg --full-gnupg --apply` instead replaces `~/.gnupg`, moving
  the previous directory aside.
- The Git profile is restored to `~/.config/git/git-profile.conf`.
- Nothing is deleted, and `pem-archive/` is never restored automatically.

## 5. Regenerate Git identity

```bash
mm install
```

This turns the restored profile into per-forge identity files and `includeIf`
rules. Forge credentials are not backed up, so the first push may require
authentication again.

Enable commit signing only when the restored GPG key should be used for it:

```bash
git config --global user.signingkey <key-id>
git config --global commit.gpgsign true
```

## 6. Optional: load an SSH key

```bash
ssh-add ~/.ssh/<key-for-that-endpoint>
```

Add `--apple-use-keychain` only if you intentionally want macOS Keychain to
remember that key's passphrase. Keep one key per purpose and use explicit
`Host` blocks with `IdentitiesOnly yes` rather than a catch-all `Host *` key.

## 7. Verify

```bash
git -C ~/Repositories/dev/mac-workstation fetch
git -C ~/Repositories/dev/mac-workstation var GIT_AUTHOR_IDENT
gpg --list-secret-keys --keyid-format LONG
mm doctor
mm selftest
```

`fetch` proves network access; `git var` proves commit identity. `mm doctor`
checks the complete installed state and `mm selftest` exercises its safeguards.

An absent vault aborts the restore instead of creating an empty one.
