### Restore on a new Mac

After a clean macOS install, `~/.ssh` and the GPG keyring are gone but the vault in iCloud Drive still holds them. Restore in this order.

**1. Wait for iCloud Drive to download the vault.** A sparsebundle that is still a placeholder cannot be mounted. Open iCloud Drive and confirm `Secure Vault` has no download arrow, or check that no placeholders remain:

```bash
find ~/Library/Mobile\ Documents/com~apple~CloudDocs/Secure\ Vault -name '*.icloud'
```

**2. Run the installer first.** `mm restore` needs `rsync`, `gpg` and the `mm` command itself:

```bash
git clone https://github.com/tommiec/mac-workstation.git ~/Repositories/dev/mac-workstation
bash ~/Repositories/dev/mac-workstation/scripts/mm_install.sh
```

This run reports *"No git profile yet"* and continues. That is expected: the
commit identity comes out of the vault in step 4, so it cannot exist yet. You
run `mm install` once more in step 6 to turn it into the identity files. Until
then git refuses to commit, which is the intended behaviour rather than a
broken install.

Note that this installs the whole `Brewfile` and pulls every model in `OLLAMA_MODELS` — tens of gigabytes and a long wait. If you only need your SSH keys back right now, skip ahead and call the script directly; it needs nothing beyond the `rsync` that ships with macOS:

```bash
bash ~/Repositories/dev/mac-workstation/scripts/mm_restore.sh --ssh
```

**3. Preview the restore.** `mm restore` is a dry run unless you pass `--apply`. It reports how old the backup is and lists every file it would touch, without writing to `~/.ssh` or `~/.gnupg`. It does still mount the vault and record a run status:

```bash
mm restore
```

**4. Apply it.** macOS asks for the vault password when the sparsebundle is mounted; the script never sees, stores or logs it.

```bash
mm restore --apply
```

An existing `~/.ssh` is never overwritten in place: it is moved to `~/.ssh.pre-restore-<timestamp>` first, so a mistaken run costs a rename, not your keys. If that path somehow already exists the restore refuses rather than nesting one directory inside the other. Afterwards `~/.ssh` is forced back to `700`, private keys to `600`, and public keys and `known_hosts` to `644` — OpenSSH refuses keys whose permissions are too open, and the vault does not reliably preserve modes.

The GPG half behaves differently, and deliberately so. The default imports the portable exports **into** the existing keyring rather than replacing it: keys already present survive, but ownertrust values for keys in the backup are overwritten. The current trust database is exported to `~/.gnupg/ownertrust.pre-restore-<timestamp>.txt` first so that part stays reversible. If you want the keyring replaced wholesale — the exact-copy restore — use `--full-gnupg`, which stops the GPG agent and moves the old `~/.gnupg` aside like the SSH path does.

Use `--ssh` or `--gpg` to restore one half only.

**5. Optional — load an SSH key into the agent and Keychain**, so its passphrase
is asked once rather than every connection. Only worth doing for a key you use
interactively; a key an automated job reads straight from disk needs nothing
here.

```bash
ssh-add ~/.ssh/<key-for-that-endpoint>
```

There is no default key name to fill in: keys here are named after the endpoint
they belong to, one per purpose, so substitute the actual filename. `ls ~/.ssh`
shows what came back.

That loads the key for this login session only. Adding `--apple-use-keychain`
writes the passphrase into the login Keychain permanently, so the key unlocks
without ever asking again. That is a deliberate trade — convenience against a
passphrase that now lives on disk — so it stays opt-in rather than the default
here.

**6. Regenerate the git identity.** `mm restore` brought back
`~/.config/git/git-profile.conf` from the vault, but the files git actually
reads are generated from it:

```bash
mm install
```

This writes `~/.config/git/identity-<forge>` and the `includeIf` rules in
`~/.gitconfig`. Identity is never set globally — it follows the remote — so
until this runs, every commit fails with *"Author identity unknown"*. That
failure is by design: `user.useConfigOnly` makes git refuse rather than commit
under an address guessed from the hostname. See `~/Repositories/GIT.md`.

Forge credentials are a separate matter: the Keychain is deliberately not backed
up, so the first `git push` to each forge asks you to authenticate again.

Add signing only if the restored GPG key is meant for it:

```bash
git config --global user.signingkey <key-id>
git config --global commit.gpgsign true
```

**7. Verify.**

```bash
git -C ~/Repositories/dev/mac-workstation fetch
git -C ~/Repositories/dev/mac-workstation var GIT_AUTHOR_IDENT
gpg --list-secret-keys --keyid-format LONG
mm doctor
mm selftest
```

Those first two check different halves and neither substitutes for the other.
The `fetch` proves **access**: the credential helper and the network. It never
writes a commit, so it says nothing about who you would commit as. `git var
GIT_AUTHOR_IDENT` proves the **identity**, and must print a name and address
rather than an error. `mm doctor` then does both across every repository at
once, which is why it is the real verification and these two are just the quick
manual spot check.

`ssh -T git@github.com` is **not** in this list — it tests an authentication
path this setup does not use, and would fail for a reason that has nothing to do
with the restore. Run it only if you have deliberately moved GitHub remotes to
SSH and registered a GitHub-specific key.

`ssh-add -l` is an optional agent check, not a pass/fail one: with no key loaded
it prints "The agent has no identities" and exits 1, which is normal and does
not mean the restore failed.

SSH keys here are for their own endpoints, not for git. Keep one key per
purpose, named after that purpose, and give each its own `Host` block in
`~/.ssh/config` with `IdentitiesOnly yes` — never a `Host *` entry, which would
offer the wrong key to every server you touch. `~/.ssh/config` is picked up by
the SSH backup automatically; the real hostnames stay out of this repository.

`mm doctor` warns about a missing `~/.ssh`, so a clean run there confirms the SSH half.

Two things `mm restore` deliberately leaves alone. `pem-archive/` is manual storage and is only reported, never copied back. And an absent vault aborts the restore instead of creating an empty one, so a not-yet-downloaded iCloud file can never be mistaken for an empty backup.
