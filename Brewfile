# Brewfile — all Homebrew-managed apps and CLI tools for this workstation.
# Installed by 'mm install' via 'brew bundle'. Fork note: replace this list
# with your own before running the installer.

# ── Casks: Development ──────────────────────────────────
cask "dash"
cask "docker-desktop"
cask "github"
cask "gitkraken"
cask "jetbrains-toolbox"
cask "postman"
cask "visual-studio-code"
cask "zed"

# ── Casks: AI / media ───────────────────────────────────
cask "chatgpt"
cask "claude"
# google-gemini, not "gemini" — that cask is MacPaw's duplicate file cleaner.
cask "google-gemini"
cask "macwhisper"
cask "vlc"

# ── Casks: Communication / browser ──────────────────────
cask "discord"
cask "firefox"
cask "microsoft-teams"
cask "whatsapp"

# ── Casks: Productivity ─────────────────────────────────
# Managed as separate casks; do not add microsoft-office alongside them.
cask "microsoft-excel"
cask "microsoft-word"

# ── Casks: Security / networking ────────────────────────
cask "balenaetcher"
cask "burp-suite"
cask "cyberduck"
cask "gpg-suite"
cask "malwarebytes"
cask "raspberry-pi-imager"
cask "wireshark-app"

# ── Casks: System utilities ─────────────────────────────
cask "appcleaner"
cask "keepingyouawake"
cask "monitorcontrol"
cask "rectangle"
cask "utm"

# ── Casks: Data / modeling ──────────────────────────────
cask "mysqlworkbench"
# visual-paradigm: cask broken upstream (vendor re-uploaded/unsigned builds,
# 18.1 bump rejected in Homebrew/homebrew-cask#271475); re-add once a signed
# release lands.

# ── CLI: Development ────────────────────────────────────
brew "git"
brew "shellcheck"

# ── CLI: Python / AI ────────────────────────────────────
brew "ollama"
brew "uv"

# ── CLI: DevOps / containers / cloud-native ─────────────
# docker CLI: shipped by the docker-desktop cask, not the formula (they fight
# over the same symlinks in the Homebrew prefix).
brew "docker-compose"
brew "trivy"

# ── CLI: Security ───────────────────────────────────────
brew "john-jumbo"
brew "sqlmap"
brew "virustotal-cli"

# ── CLI: Network ────────────────────────────────────────
brew "nmap"
brew "wget"
# wireshark CLI (tshark, dumpcap, editcap, ...): shipped by the wireshark-app
# cask, not the formula (they fight over the same symlinks).

# ── CLI: File / archive / document tools ────────────────
brew "dos2unix"
brew "exiftool"
brew "p7zip"
brew "pandoc"
brew "tesseract"
brew "tesseract-lang"
brew "weasyprint"

# ── CLI: Cross-platform administration ──────────────────
brew "powershell"
