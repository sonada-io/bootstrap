#!/usr/bin/env bash
# Sonada R&D laptop setup. macOS only. Safe to run again: it skips what is already installed.
#
#   curl -fsSL https://raw.githubusercontent.com/sonada-io/bootstrap/main/bootstrap.sh | bash
#
# Edit the lists below to change what every new R&D laptop gets.
set -euo pipefail

# ---- what gets installed ----------------------------------------------------
# "cask:App name in /Applications". An app already in /Applications is left alone.
APPS=(
  "google-chrome:Google Chrome"
  "claude:Claude"
  "chatgpt:ChatGPT"
  "slack:Slack"
  "notion:Notion"
  "docker-desktop:Docker"
)
TAPS=(hashicorp/tap)
FORMULAE=(git gh uv node awscli hashicorp/tap/terraform python@3.15)
NPM_VERSION="11.19"
ORG="sonada-io"
REPOS=(demo skills)
DEST="$HOME/sonada-io"

# ---- helpers ----------------------------------------------------------------
say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok() { printf '    \033[0;32m%s\033[0m\n' "$*"; }
warn() { printf '    \033[0;33m%s\033[0m\n' "$*"; }
FAILED=()
# One failed install doesn't stop the rest. Failures are listed at the end.
try() {
  local label="$1"
  shift
  if ! "$@"; then
    warn "$label failed, continuing"
    FAILED+=("$label")
  fi
}
# Piped through curl, stdin is the script itself, so anything interactive reads from the terminal.
tty_run() { "$@" </dev/tty; }

# The last thing every run prints, including runs that stop early.
# It fails if anything didn't finish, so the whole run exits non-zero.
summary() {
  say "Done"
  if ((${#FAILED[@]})); then
    warn "These didn't finish: ${FAILED[*]}. Run the command again, or ask in #onboarding."
  fi
  cat <<'MSG'
    Next:
    1. Open Chrome and sign in with your Sonada account.
    2. Open Docker once and accept its terms.
    3. Go back to the welcome email and continue with the next step.
MSG
  ((${#FAILED[@]} == 0))
}

# Everything runs inside main(), called on the last line. Bash then reads the whole file before running any of it,
# so a cut-off download runs nothing, and a program that reads standard input can't swallow the rest of the script.
main() {
  [[ "$(uname -s)" == "Darwin" ]] || { echo "This script is for macOS."; exit 1; }

  # ---- 1. Xcode command line tools (git, compilers) ---------------------------
  say "Xcode command line tools"
  if xcode-select -p >/dev/null 2>&1; then
    ok "already installed"
  else
    xcode-select --install || true
    echo "A window opened to install the command line tools. Finish it, then run the same command again."
    exit 0
  fi

  # ---- 2. Homebrew -------------------------------------------------------------
  say "Homebrew"
  if [[ -x /opt/homebrew/bin/brew ]]; then BREW=/opt/homebrew/bin/brew; else BREW=/usr/local/bin/brew; fi
  if [[ -x "$BREW" ]]; then
    ok "already installed"
  else
    echo "Homebrew needs your Mac password once."
    tty_run sudo -v
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then BREW=/opt/homebrew/bin/brew; else BREW=/usr/local/bin/brew; fi
  fi
  eval "$("$BREW" shellenv)"
  if ! grep -qs 'brew shellenv' "$HOME/.zprofile"; then
    echo "eval \"\$($BREW shellenv)\"" >>"$HOME/.zprofile"
    ok "added Homebrew to ~/.zprofile"
  fi

  # ---- 3. Apps -----------------------------------------------------------------
  say "Apps"
  for entry in "${APPS[@]}"; do
    cask="${entry%%:*}"
    app="${entry#*:}"
    if [[ -d "/Applications/$app.app" ]]; then
      ok "$app: already installed"
    else
      try "$app" brew install --cask "$cask"
    fi
  done

  # ---- 4. Developer tools ------------------------------------------------------
  say "Developer tools"
  for tap in "${TAPS[@]}"; do try "tap $tap" brew tap "$tap"; done
  for formula in "${FORMULAE[@]}"; do
    if brew list --formula "${formula##*/}" >/dev/null 2>&1; then
      ok "${formula##*/}: already installed"
    else
      try "${formula##*/}" brew install "$formula"
    fi
  done

  if command -v npm >/dev/null && [[ "$(npm --version)" != "$NPM_VERSION".* ]]; then
    try "npm $NPM_VERSION" npm install --global "npm@$NPM_VERSION"
  fi

  # ---- 5. GitHub ---------------------------------------------------------------
  say "GitHub"
  if ! command -v gh >/dev/null; then
    warn "gh isn't installed, so GitHub sign-in and cloning are skipped."
    FAILED+=("GitHub sign-in")
    summary
    return
  fi
  if gh auth status >/dev/null 2>&1; then
    ok "already signed in"
  else
    echo "Sign in with your GitHub account (the one invited to $ORG). A browser opens."
    if ! tty_run gh auth login --hostname github.com --git-protocol https --web || ! gh auth status >/dev/null 2>&1; then
      warn "GitHub sign-in didn't finish, so cloning is skipped."
      FAILED+=("GitHub sign-in")
      summary
      return
    fi
  fi
  try "git credentials for GitHub" gh auth setup-git

  # ---- 6. Repos ----------------------------------------------------------------
  say "Repos in $DEST"
  # A new hire's org invite is still pending here. Accept it if GitHub matched it to this account.
  if [[ "$(gh api "user/memberships/orgs/$ORG" --jq .state 2>/dev/null || true)" == "pending" ]]; then
    gh api --method PATCH "user/memberships/orgs/$ORG" -f state=active >/dev/null && ok "accepted the $ORG invite"
  fi
  mkdir -p "$DEST"
  NOT_YET=()
  for repo in "${REPOS[@]}"; do
    if [[ -d "$DEST/$repo/.git" ]]; then
      ok "$repo: already cloned"
    elif gh repo view "$ORG/$repo" --json name >/dev/null 2>&1; then
      try "clone $repo" gh repo clone "$ORG/$repo" "$DEST/$repo"
    else
      NOT_YET+=("$repo")
    fi
  done
  if ((${#NOT_YET[@]})); then
    warn "No access yet to: ${NOT_YET[*]}."
    warn "Accept the $ORG invite in your Sonada Gmail, then run this command again to clone them."
  fi

  summary
}

main "$@"
