#!/usr/bin/env bash
# Sonada laptop setup. macOS only. Safe to run again: it skips what is already installed.
#
#   curl -fsSL https://raw.githubusercontent.com/sonada-io/bootstrap/main/bootstrap.sh | bash -s -- --role rnd
#
# --role is rnd, product or ops. Everyone gets the apps, Claude Code and Mila. R&D also gets the developer tools,
# GitHub and the repos. Edit the lists below to change what a new laptop gets.
set -euo pipefail

# ---- what gets installed ----------------------------------------------------
# "cask:App name in /Applications". An app already in /Applications is left alone.
APPS=(
  "google-chrome:Google Chrome"
  "claude:Claude"
  "chatgpt:ChatGPT"
  "slack:Slack"
  "notion:Notion"
)
RND_APPS=("docker-desktop:Docker")
TAPS=(hashicorp/tap)
FORMULAE=(git gh uv node awscli hashicorp/tap/terraform python@3.15)
NPM_VERSION="11.19"
ORG="sonada-io"
REPOS=(demo skills)
DEST="$HOME/sonada-io"

MILA_REPO="island-io/mila"
MILA_APP="/Applications/Mila.app"
MILA_MCP="$MILA_APP/Contents/MacOS/mila-mcp"
MILA_CONFIG_URL="https://raw.githubusercontent.com/sonada-io/bootstrap/main/sonada.milaconfig"
CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
CLAUDE="$HOME/.local/bin/claude"
MILA_CONFIG_DONE="$HOME/Library/Application Support/Sonada/milaconfig-opened"
MILA_READY=0

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

usage() {
  echo "Usage: bootstrap.sh --role rnd|product|ops"
  echo "Copy the command from your welcome email: it has your role."
}

ROLE=""
# The last thing every run prints, including runs that stop early.
# It fails if anything didn't finish, so the whole run exits non-zero.
summary() {
  say "Done"
  if ((${#FAILED[@]})); then
    warn "These didn't finish: ${FAILED[*]}. Run the command again, or ask in #onboarding."
  fi
  local n=1
  echo "    Next:"
  echo "    $((n++)). Open Chrome and sign in with your Sonada account."
  if ((MILA_READY)); then echo "    $((n++)). Quit Claude and open it again, so it loads Mila."; fi
  if [[ "$ROLE" == "rnd" ]]; then echo "    $((n++)). Open Docker once and accept its terms."; fi
  echo "    $((n++)). Go back to the welcome email and continue with the next step."
  ((${#FAILED[@]} == 0))
}

install_apps() {
  local entry cask app
  for entry in "$@"; do
    cask="${entry%%:*}"
    app="${entry#*:}"
    if [[ -d "/Applications/$app.app" ]]; then
      ok "$app: already installed"
    else
      try "$app" brew install --cask "$cask"
    fi
  done
}

claude_code_install() {
  curl -fsSL https://claude.ai/install.sh | bash
  [[ -x "$CLAUDE" ]]
}

claude_code_sign_in() {
  echo "Sign in to Claude with your Sonada account. A browser opens."
  tty_run "$CLAUDE" auth login || true
  "$CLAUDE" auth status >/dev/null 2>&1
}

# The latest Mila release from GitHub: download the DMG, check Apple's signature, copy the app to /Applications.
# The copy goes to a temp folder first, so a failed run never leaves a half-copied app behind.
mila_install() {
  local major url tmp rc=0
  major="$(sw_vers -productVersion | cut -d. -f1)"
  if ((major < 14)); then
    warn "Mila needs macOS 14 or later. Update macOS, then run the command again."
    return 1
  fi
  url="$(curl -fsSL "https://api.github.com/repos/$MILA_REPO/releases/latest" |
    grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed -E 's/.*"(https[^"]+)"/\1/')" || true
  if [[ -z "$url" ]]; then
    warn "couldn't find Mila's download on GitHub"
    return 1
  fi
  tmp="$(mktemp -d)"
  mkdir "$tmp/mnt"
  curl -fL --progress-bar -o "$tmp/Mila.dmg" "$url" || rc=$?
  if ((rc == 0)); then
    hdiutil attach -nobrowse -quiet -mountpoint "$tmp/mnt" "$tmp/Mila.dmg" || rc=$?
  fi
  if ((rc == 0)); then
    ditto "$tmp/mnt/Mila.app" "$tmp/Mila.app" || rc=$?
    hdiutil detach -quiet "$tmp/mnt" || true
  fi
  if ((rc == 0)); then
    # curl sets no quarantine flag, so Gatekeeper never looks at this app. Check the signature ourselves.
    if ! codesign --verify --deep --strict "$tmp/Mila.app" || ! spctl --assess --type execute "$tmp/Mila.app"; then
      warn "Mila's download isn't signed and notarized by Apple, so it wasn't installed"
      rc=1
    fi
  fi
  if ((rc == 0)); then
    rm -rf "$MILA_APP"
    mv "$tmp/Mila.app" "$MILA_APP" || rc=$?
  fi
  rm -rf "$tmp"
  return "$rc"
}

# Mila shows what the file changes and asks before applying it. Opened until it worked once, then never again.
mila_config() {
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/sonada.milaconfig" "$MILA_CONFIG_URL" &&
    open -a "$MILA_APP" "$tmp/sonada.milaconfig" &&
    mkdir -p "$(dirname "$MILA_CONFIG_DONE")" && touch "$MILA_CONFIG_DONE"
}

# Registers Mila's MCP helper in Claude Desktop, keeping any other servers in the file.
mila_desktop() {
  /usr/bin/python3 - "$CLAUDE_DESKTOP_CONFIG" "$MILA_MCP" <<'PY'
import json, os, sys

path, command = sys.argv[1], sys.argv[2]
config = {}
if os.path.exists(path):
    with open(path) as f:
        config = json.load(f)
servers = config.setdefault("mcpServers", {})
if servers.get("mila", {}).get("command") == command:
    print("    Mila in Claude Desktop: already added")
    sys.exit(0)
servers["mila"] = {"command": command}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path + ".tmp", "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
os.replace(path + ".tmp", path)
print("    added Mila to Claude Desktop")
PY
}

mila_code() {
  if "$CLAUDE" mcp get mila >/dev/null 2>&1; then
    ok "Mila in Claude Code: already added"
  else
    "$CLAUDE" mcp add --scope user mila -- "$MILA_MCP"
  fi
}

# Everything runs inside main(), called on the last line. Bash then reads the whole file before running any of it,
# so a cut-off download runs nothing, and a program that reads standard input can't swallow the rest of the script.
main() {
  while (($#)); do
    case "$1" in
      --role) ROLE="${2:-}"; shift 2 || shift ;;
      --role=*) ROLE="${1#*=}"; shift ;;
      *) usage; exit 1 ;;
    esac
  done
  case "$ROLE" in rnd | product | ops) ;; *) usage; exit 1 ;; esac
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
  install_apps "${APPS[@]}"
  if [[ "$ROLE" == "rnd" ]]; then install_apps "${RND_APPS[@]}"; fi

  # ---- 4. Claude Code ----------------------------------------------------------
  say "Claude Code"
  if [[ -x "$CLAUDE" ]]; then
    ok "already installed"
  else
    try "Claude Code" claude_code_install
  fi
  export PATH="$HOME/.local/bin:$PATH"
  if ! grep -qs '.local/bin' "$HOME/.zprofile"; then
    # shellcheck disable=SC2016 # written as is, expanded when the shell starts
    echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.zprofile"
    ok "added ~/.local/bin to ~/.zprofile"
  fi
  if [[ ! -x "$CLAUDE" ]]; then
    : # the install failed above, so there is nothing to sign in to
  elif "$CLAUDE" auth status >/dev/null 2>&1; then
    ok "already signed in"
  else
    try "Claude Code sign-in" claude_code_sign_in
  fi

  # ---- 5. Mila -----------------------------------------------------------------
  say "Mila"
  # The MCP helper is the last file in the bundle that matters to us. Without it the app is missing, broken or too old.
  if [[ -x "$MILA_MCP" ]]; then
    ok "already installed"
  elif mila_install; then
    ok "installed"
  else
    FAILED+=("Mila")
  fi
  if [[ -x "$MILA_MCP" ]]; then
    if [[ ! -e "$MILA_CONFIG_DONE" ]]; then try "Mila settings" mila_config; fi
    if mila_desktop; then
      MILA_READY=1
    else
      warn "Mila in Claude Desktop failed, continuing"
      FAILED+=("Mila in Claude Desktop")
    fi
    if [[ -x "$CLAUDE" ]]; then try "Mila in Claude Code" mila_code; fi
  fi

  if [[ "$ROLE" != "rnd" ]]; then
    summary
    return
  fi

  # ---- 6. Developer tools (R&D) ------------------------------------------------
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

  # ---- 7. GitHub (R&D) ---------------------------------------------------------
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

  # ---- 8. Repos (R&D) ----------------------------------------------------------
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
