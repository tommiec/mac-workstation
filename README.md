# mac-workstation

My personal macOS workstation setup: Homebrew tooling, scheduled maintenance, diagnostics, and file/security triage.

## Why this exists

A consistent, low-effort way to bootstrap my Mac, keep core tooling maintained, and support day-to-day IT, DevOps, AI, and security work.

One-time setup. Runs automatically. Manual control when needed.

> **Using this yourself?** The app list in the `Brewfile` is mine. Fork the repo and replace it with your own before running the installer.
>
> `mm` stands for **Mac Manager**.

## Scripts

| Script | Purpose |
|---|---|
| `mm_install.sh` | Bootstrap setup (repo, CLI, launchd) |
| `mm_auto.sh` | Automated weekly maintenance (launchd) |
| `mm_maintain.sh` | Run maintenance now: Homebrew, optional cask upgrades, DNS flush, macOS updates, optional SSH backup, optional QuickTime history cleanup |
| `mm_doctor.sh` | Health checks and diagnostics (`mm doctor`) |
| `mm_triage.sh` | Quick file/malware triage with hash, VirusTotal and strings (`mm triage`) |
| `mm_backup_ssh.sh` | Backup `~/.ssh` to an encrypted iCloud sparsebundle (called by `mm maintain`) |
| `mm_backup_gpg.sh` | Backup GPG keys, ownertrust and `~/.gnupg` to the encrypted iCloud sparsebundle |
| `mm_restore.sh` | Restore SSH material, GPG material and the git identity from the vault onto a new Mac (`mm restore`, dry run by default) |
| `mm_selftest.sh` | Assert that the git identity hooks refuse what the policy forbids (`mm selftest`) |
| `mm_common.sh` | Shared configuration and helpers |

The managed apps and CLI tools are declared in the repo-root `Brewfile` and installed with `brew bundle`.

## How it works

Scripts are managed using a **repo + CLI model**:

```
~/Repositories/dev/mac-workstation      → source and runtime (git repo)
~/.local/bin/mm                         → CLI entrypoint
~/Library/Logs/mac_manager/             → logs
```

- The repo contains the runtime scripts and is version-controlled
- The `mm` command provides a simple interface
- launchd runs the auto-maintenance script directly from the repository

## Installation

Clone the repo and run the installer once:

```bash
mkdir -p ~/Repositories/dev
git clone https://github.com/tommiec/mac-workstation.git ~/Repositories/dev/mac-workstation
bash ~/Repositories/dev/mac-workstation/scripts/mm_install.sh
```

If `git` is not available yet, run `xcode-select --install`, complete the
Command Line Tools installation, and then repeat the commands above.

The installer will:
- set up Homebrew (if needed)
- install all apps and CLI tools from the `Brewfile` (via `brew bundle`)
- install the `mm` command in `~/.local/bin`
- configure global Git excludes, a local Git hooks path and the per-forge commit
  identity
- start Ollama as a persistent user service and pull the managed models
- register the weekly launchd job

The installer ensures that the user-local command folder is in your shell path
by adding this line to `~/.zshrc` when it is not already present:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

To update later:

```bash
cd ~/Repositories/dev/mac-workstation
git pull --ff-only
```

Normal script changes are active directly after `git pull`. Run `mm install` only if you changed installer-managed setup: the app list, LaunchAgent schedule, or `mm` wrapper.

### Ollama for the local network

Homebrew installs the Ollama binary. `mm install` stops Homebrew's optional
service and registers one Mac Manager-owned LaunchAgent
(`local.mac-manager.ollama`) that listens on all network interfaces at port
`11434`. Its settings cannot be overwritten by `brew services` or an Ollama
upgrade. The installer then installs these models when missing:

```text
devstral:24b
qwen3-coder:30b
gemma3:27b
qwen2.5-coder:14b
```

Allow roughly 60 GB of model storage under `~/.ollama/models`. From the NAS,
test the connection using the Mac's stable LAN address:

```bash
curl http://MAC_LAN_IP:11434/api/tags
```

Large model pulls use up to four attempts with delays of 10, 20, and 40
seconds. Ollama retains partial downloads between attempts, resumes them on the
next `pull`, and verifies every downloaded blob against its SHA-256 digest
before writing the model manifest. The installer additionally requires
`ollama show` to read the completed model successfully. Re-running `mm install`
continues any model that still failed after all attempts.

The service enables Flash Attention, uses a `q8_0` KV cache, and limits Ollama
to one loaded model and one parallel request. This is intentional for a Mac
with 36 GB unified memory: every managed model fits individually without trying
to keep multiple 14–19 GB model images resident at once.

Mac Manager owns the persistent configuration at
`~/Library/LaunchAgents/local.mac-manager.ollama.plist`. `RunAtLoad` and
`KeepAlive` make it start after login and restart after a crash. `mm auto`
compares the running server version with the installed CLI and restarts a loaded
agent when they differ, including after a manual or partially failed Homebrew
upgrade. Re-running `mm install` leaves an identical loaded service untouched,
so active models and NAS requests are not interrupted.

Ollama's local API has no authentication. Binding it to `0.0.0.0:11434`
therefore makes model execution available to every device that can reach that
port. Use this only on a trusted LAN, do not forward port `11434` on the router,
and restrict access with the macOS firewall or a separate authenticated reverse
proxy when needed. The Mac must be logged in and awake because Ollama runs as a
user LaunchAgent; reserving its LAN address in DHCP keeps the NAS endpoint
stable. Remember that a MacBook roams: on café, hotel, or guest Wi-Fi, the
unauthenticated API is exposed to peers on that network too. Stop it before
leaving a trusted LAN with:

```bash
launchctl bootout "gui/$(id -u)/local.mac-manager.ollama"
```

Start it again from its persistent configuration with:

```bash
launchctl bootstrap "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/local.mac-manager.ollama.plist"
```

### Local Git config bootstrap

`mm install` configures the machine-wide Git hygiene baseline:

- `configs/git-ignore-global` is copied to `~/.config/git/ignore`
- Git is configured with `core.excludesFile=~/.config/git/ignore`
- Git is configured with `core.hooksPath=~/.config/git/hooks`

The repository also contains the managed local ignore rules and the managed
hooks:

```text
configs/
  ignore.local
  git-profile.conf.example
  hooks/
    commit-msg
    git-profile-check
    pre-commit
    pre-push
```

During installation:

- `ignore.local` is copied to `~/.config/git/ignore.local`
- every file in `hooks/` is copied to `~/.config/git/hooks/` and made executable
- `ignore.local` is appended to the generated `~/.config/git/ignore`

This keeps all Git hygiene configuration versioned and reproducible from the
same source. `mm doctor` verifies that the installed local excludes and every
managed hook match the repository versions.

#### Commit identity

Identity is set **per forge**, never globally, so repos on GitHub and on the
self-hosted Forgejo each get the right author without per-clone configuration.
`mm install` generates `~/.config/git/identity-<forge>` plus the matching
`includeIf` rules in `~/.gitconfig` from a single machine-local file:

```text
~/.config/git/git-profile.conf
```

That file is the only place holding the name, the address and the forge URLs. It
is **not** stored in this repository: this repo is public, and those values are
personal data and internal network topology. `configs/git-profile.conf.example`
documents the format; the real file is mirrored into the encrypted vault by the
SSH and GPG backup runs and restored by `mm restore`.

The managed `pre-commit` and `pre-push` hooks reject a per-repository identity
override, an unknown remote, and outgoing commits with the wrong author. Full
policy, recovery procedure and threat model: `~/Repositories/GIT.md`.

## Usage

**Automatic** — runs every Saturday at 02:00 via launchd.

**Commands:**

```bash
mm auto      # run automated maintenance now
mm maintain  # run maintenance now (interactive prompts)
mm install   # re-run setup
mm doctor    # check system health
mm selftest  # verify the git identity hooks refuse what they should
mm triage <file>  # inspect a suspicious file
mm help      # show available commands
```

`mm doctor` and `mm selftest` are complements: doctor audits how this machine is
configured, selftest asserts in a throwaway sandbox that the managed git hooks
actually reject a per-repo identity override, an unknown remote and an outgoing
commit with the wrong author. Doctor alone only ever exercises the happy path.

`mm maintain` reports drift so keeping, uninstalling, or adopting into the `Brewfile` stays a deliberate choice: Homebrew packages installed outside the `Brewfile`, and apps in `/Applications` that did not come in through Homebrew (labelled App Store or manual install). It then asks before taking optional actions: upgrading outdated Homebrew casks, installing macOS updates, backing up `~/.ssh` and GPG keys/trust to the encrypted iCloud vault, and clearing QuickTime Player's recent documents history. The QuickTime cleanup removes QuickTime's app-specific recent-document shared-file-list entries and legacy QuickTime preference keys. It does not delete media files and does not clear system-wide macOS Recent Items.

## File triage

File triage is a deliberate part of this workstation setup, not an add-on: the machine should be able to handle quick, self-contained file research on its own, without reaching for a separate analysis environment first.

Use `mm triage` for a quick first look at a suspicious file:

```bash
mm triage ~/Downloads/example.exe
```

The command:
- identifies the file type using `file`
- calculates the SHA256 hash
- looks up the hash in VirusTotal when the `vt` CLI is available
- shows a short hex preview
- checks magic bytes against common file types
- flags mismatches between file extension and detected content
- extracts quick indicators such as URLs, IPs, shell commands and suspicious strings
- prints a simple triage score
- opens extracted strings in `less` for manual review

The installer installs `virustotal-cli`. The triage script uses the CLI command `vt` for lookups, so configure the `vt` CLI with your VirusTotal API key first. The string view opens in `less`; press `q` to exit it.

## Secrets & SSH keys

Avoid storing API keys and tokens as plain text in dotfiles. On macOS, Keychain or Apple Passwords is a better place for them.

For one-off Keychain use, source the helper file first:

```bash
source ~/Repositories/dev/mac-workstation/scripts/mm_common.sh
keychain_set "ANTHROPIC_API_KEY"   # store once; prompts for the secret
keychain_get "ANTHROPIC_API_KEY"   # retrieve
```

In `~/.zshrc`, load the key directly from Keychain instead of hardcoding it:

```bash
export ANTHROPIC_API_KEY="$(security find-generic-password -a "$USER" -s ANTHROPIC_API_KEY -w 2>/dev/null)"
```

`mm doctor` scans shell dotfiles for likely plain-text secrets and masks their values in the output. It also shows an inventory of SSH private keys in `~/.ssh` — name, type, bits, fingerprint, and modification date — and warns on loose directory/file permissions, DSA keys, and short RSA keys (< 3072b). Only group or other access triggers a warning; common safe modes are `600` and `400`. For SSH trust awareness, it also summarizes `known_hosts` with visible and hashed host patterns, modification date, and a small visible sample when available.

Use passphrases for SSH private keys. macOS can remember those passphrases in Keychain.

### Encrypted secrets vault

For secrets that should be recoverable on a new Mac but should not live as plain files in iCloud Drive, this setup uses one encrypted sparsebundle:

```bash
~/Library/Mobile Documents/com~apple~CloudDocs/Secure Vault/Secrets.sparsebundle
```

macOS asks for the vault password each time it needs to be mounted. On the first run it also asks you to choose that password — store it in your password manager. The script never stores or logs the vault password.

Inside the mounted vault, SSH, GPG and PEM material have different lifecycles:

```text
ssh-backup/
gpg-backup/
pem-archive/
```

`ssh-backup/` is managed by the optional SSH backup prompt in `mm maintain`. It mirrors `~/.ssh` into the encrypted vault and may overwrite that backup on future runs.

`gpg-backup/` is managed by the optional GPG backup prompt in `mm maintain`. It stores `latest/portable/` exports (`public-keys.asc`, `secret-keys.asc`, `ownertrust.txt`, and `secret-keys-list.txt`), `latest/full-gnupg/.gnupg/`, and timestamped archives under `archives/`.

Both backups are restored with `mm restore`; see [Restore on a new Mac](#restore-on-a-new-mac). The equivalent manual GPG import, if you prefer to do it by hand:

```bash
cd "/Volumes/Secrets/gpg-backup/latest/portable"
gpg --import public-keys.asc
gpg --import secret-keys.asc
gpg --import-ownertrust ownertrust.txt
```

If you need an exact full restore instead, copy `gpg-backup/latest/full-gnupg/.gnupg/` back to `~/.gnupg` while GPG is not running, then restart GPG/GPG Suite. `mm restore --gpg --full-gnupg --apply` does the same thing and stops the agent first.

`pem-archive/` is manual storage for PEM/private-key files that should live only inside the encrypted vault. The SSH backup command creates the folder but never syncs, cleans, or overwrites it.

Unmount the vault after use and let iCloud Drive finish syncing before shutting down or editing it elsewhere.

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

**5. Load the SSH key into the agent and Keychain**, so the passphrase is asked once rather than every connection:

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

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
ssh -T git@github.com
gpg --list-secret-keys --keyid-format LONG
mm doctor
```

`mm doctor` warns about a missing `~/.ssh`, so a clean run there confirms the SSH half.

Two things `mm restore` deliberately leaves alone. `pem-archive/` is manual storage and is only reported, never copied back. And an absent vault aborts the restore instead of creating an empty one, so a not-yet-downloaded iCloud file can never be mistaken for an empty backup.

## Notes

- Uses a LaunchAgent (user context, no root daemon)
- Writes logs and last-run status under `~/Library/Logs/mac_manager/`
- Weekly maintenance removes `auto_*.log` and `maintain_*.log` files older than
  60 days and truncates Ollama output logs when they exceed 50 MiB
- Safe to re-run `mm install` at any time, but usually only needed after installer-managed setup changes
- `mm doctor` can be used to validate the setup and inspect the last recorded run for each script
- `mm doctor` is read-only: it reports drift (including whether the checkout is behind GitHub) but never changes the system; updating happens via `git pull --ff-only` or the weekly auto run
- Global Git hygiene is installed by `mm install`: shared excludes and hooks come
  from this repo and are installed under `~/.config/git`, while the commit
  identity comes from the machine-local `~/.config/git/git-profile.conf`, which
  is vault-backed and deliberately not stored here

## License

MIT — Thomas Coppens

## AI usage

AI was used as a sounding board for shell-scripting choices, error analysis and documentation structure. The design, implementation, validation and maintenance are mine.
