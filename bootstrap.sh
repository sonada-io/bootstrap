#!/usr/bin/env bash
# Sonada laptop setup. macOS only. Safe to run again: it skips what is already installed.
#
#   curl -fsSL https://raw.githubusercontent.com/sonada-io/bootstrap/main/bootstrap.sh | bash -s -- --role rnd
#
# --role is rnd, product or ops. Everyone gets oh my zsh, the apps, Claude Code and Mila. R&D and Product also get
# git, GitHub, Sonada's git settings and an SSH key. R&D also gets the developer tools and the repos. Edit the lists
# below to change what a new laptop gets.
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
CLI_CASKS=(gcloud-cli) # command line tools that brew ships as casks (no app in /Applications)
GIT_FORMULAE=(git gh)  # Product gets only these
OMZ_PLUGINS="git gh"
RND_OMZ_PLUGINS="git gh aws gcloud"
NPM_VERSION="11.19"
ORG="sonada-io"
REPOS=(demo skills)
DEST="$HOME/sonada-io"

MILA_REPO="island-io/mila"
# Apple Team ID that signs Mila's releases. Anything signed by another developer is refused, even when notarized.
# To read it from an installed Mila: codesign -dv /Applications/Mila.app 2>&1 | grep TeamIdentifier
MILA_TEAM_ID="38ZC4T8AWY"
MILA_APP="/Applications/Mila.app"
MILA_MCP="$MILA_APP/Contents/MacOS/mila-mcp"
MILA_CONFIG_URL="https://raw.githubusercontent.com/sonada-io/bootstrap/main/sonada.milaconfig"
CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
CLAUDE="$HOME/.local/bin/claude"
SONADA_DIR="$HOME/Library/Application Support/Sonada"
MILA_CONFIG_FILE="$SONADA_DIR/sonada.milaconfig"
MILA_CONFIG_DONE="$SONADA_DIR/milaconfig-opened"
MILA_READY=0

OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
# Sonada's shared git settings (aliases, push, pull, signing). Fetched on every run, so a change to the file reaches
# everyone the next time they run the script. Included at the top of ~/.gitconfig, so the person's own settings win.
GITCONFIG_URL="https://raw.githubusercontent.com/sonada-io/bootstrap/main/sonada.gitconfig"
SONADA_GITCONFIG="$HOME/.config/sonada/gitconfig"
# shellcheck disable=SC2088 # written into ~/.gitconfig as is, git expands the ~
SONADA_GITCONFIG_INCLUDE="~/.config/sonada/gitconfig"
# A Sonada-specific name, so it never replaces a personal ~/.ssh/id_ed25519.
SSH_KEY="$HOME/.ssh/id_ed25519_sonada"
# Extra GitHub scopes: upload the SSH key for sign-in and for signing, and read the Sonada email for git.
GH_SCOPES=(admin:public_key admin:ssh_signing_key user:email)

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
# Piped through curl, stdin is the script itself, so anything interactive reads from the terminal. It reads from the
# terminal's own device (/dev/ttys003 and so on), not /dev/tty: macOS can't watch /dev/tty with kqueue, so Claude
# Code's sign-in crashes on it with "EINVAL: invalid argument, kqueue".
TTY_DEV="$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ' || true)"
if [[ -n "$TTY_DEV" && "$TTY_DEV" != "??" && -r "/dev/$TTY_DEV" ]]; then TTY_DEV="/dev/$TTY_DEV"; else TTY_DEV=/dev/tty; fi
tty_run() { "$@" <"$TTY_DEV"; }

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
  if [[ -z "$MILA_TEAM_ID" ]]; then
    warn "MILA_TEAM_ID is empty in bootstrap.sh, so Mila can't be checked and wasn't installed"
    return 1
  fi
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
    # spctl proves Apple notarized it, the Team ID proves it is Mila's own developer.
    if ! codesign --verify --deep --strict "$tmp/Mila.app" || ! spctl --assess --type execute "$tmp/Mila.app"; then
      warn "Mila's download isn't signed and notarized by Apple, so it wasn't installed"
      rc=1
    elif [[ "$(codesign -dv "$tmp/Mila.app" 2>&1 | sed -n 's/^TeamIdentifier=//p')" != "$MILA_TEAM_ID" ]]; then
      warn "Mila's download is signed by an unexpected developer, so it wasn't installed"
      rc=1
    fi
  fi
  if ((rc == 0)); then
    # An old or broken Mila is moved aside, not deleted, and comes back if the new one can't be moved in.
    osascript -e 'quit app "Mila"' >/dev/null 2>&1 || true
    if [[ -e "$MILA_APP" ]]; then mv "$MILA_APP" "$tmp/Mila.old" || rc=$?; fi
  fi
  if ((rc == 0)) && ! mv "$tmp/Mila.app" "$MILA_APP"; then
    rc=1
    if [[ -e "$tmp/Mila.old" ]]; then mv "$tmp/Mila.old" "$MILA_APP" || true; fi
  fi
  rm -rf "$tmp"
  return "$rc"
}

# Mila shows what the file changes and asks before applying it. Opened until it opened once. The file stays in
# ~/Library/Application Support/Sonada, so the Set up Mila task can tell the person how to open it again.
mila_config() {
  mkdir -p "$SONADA_DIR" &&
    curl -fsSL -o "$MILA_CONFIG_FILE" "$MILA_CONFIG_URL" &&
    open -a "$MILA_APP" "$MILA_CONFIG_FILE" &&
    touch "$MILA_CONFIG_DONE"
}

# Registers Mila's MCP helper in Claude Desktop, keeping any other servers in the file. Python only edits the file
# and prints what it did, so the message goes through ok() like every other line.
mila_desktop() {
  local result
  result="$(/usr/bin/python3 - "$CLAUDE_DESKTOP_CONFIG" "$MILA_MCP" <<'PY'
import json, os, sys

path, command = sys.argv[1], sys.argv[2]
config = {}
if os.path.exists(path):
    with open(path) as f:
        config = json.load(f)
servers = config.setdefault("mcpServers", {})
if servers.get("mila", {}).get("command") == command:
    print("already")
    sys.exit(0)
servers["mila"] = {"command": command}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path + ".tmp", "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
os.replace(path + ".tmp", path)
print("added")
PY
  )" || return 1
  if [[ "$result" == "already" ]]; then ok "Mila in Claude Desktop: already added"; else ok "added Mila to Claude Desktop"; fi
}

mila_code() {
  if "$CLAUDE" mcp get mila >/dev/null 2>&1; then
    ok "Mila in Claude Code: already added"
  else
    "$CLAUDE" mcp add --scope user mila -- "$MILA_MCP" >/dev/null && ok "added Mila to Claude Code"
  fi
}

install_formulae() {
  local formula
  for formula in "$@"; do
    if brew list --formula "${formula##*/}" >/dev/null 2>&1; then
      ok "${formula##*/}: already installed"
    else
      try "${formula##*/}" brew install "$formula"
    fi
  done
}

install_cli_casks() {
  local cask
  for cask in "$@"; do
    if brew list --cask "$cask" >/dev/null 2>&1; then
      ok "$cask: already installed"
    else
      try "$cask" brew install --cask "$cask"
    fi
  done
}

# The official installer, downloaded first so a failed download runs nothing. Unattended: it doesn't change the login
# shell (zsh is already the macOS default) and doesn't start a new shell. An existing ~/.zshrc is kept as
# ~/.zshrc.pre-oh-my-zsh. Homebrew and ~/.local/bin are in ~/.zprofile, so they keep working.
oh_my_zsh_install() {
  local plugins="$1" tmp rc=0
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/install.sh" "$OMZ_INSTALL_URL" || rc=$?
  # ZSH is cleared: a terminal already running oh my zsh exports it, and the installer then refuses to run.
  if ((rc == 0)); then env -u ZSH RUNZSH=no CHSH=no sh "$tmp/install.sh" --unattended || rc=$?; fi
  rm -rf "$tmp"
  ((rc == 0)) || return "$rc"
  # Only the installer's own default line is changed, so a hand-edited ~/.zshrc is left alone.
  sed -i '' "s/^plugins=(git)\$/plugins=($plugins)/" "$HOME/.zshrc" && ok "plugins: $plugins"
}

# True when the GitHub token has every scope in GH_SCOPES. A token from before this script asked for them doesn't.
gh_has_scopes() {
  local have scope
  have="$(gh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: //p')"
  for scope in "${GH_SCOPES[@]}"; do
    [[ ", $have," == *", $scope,"* ]] || return 1
  done
}

github_sign_in() {
  local scopes
  scopes="$(IFS=,; echo "${GH_SCOPES[*]}")"
  if gh auth status >/dev/null 2>&1; then
    if gh_has_scopes; then
      ok "already signed in"
    else
      echo "GitHub needs a few more permissions, for your SSH key and your email. A browser opens."
      tty_run gh auth refresh --hostname github.com --scopes "$scopes" || return 1
    fi
  else
    echo "Sign in with the GitHub account you created from the $ORG invite (<first name>-sonada). A browser opens."
    tty_run gh auth login --hostname github.com --git-protocol ssh --web --scopes "$scopes" || return 1
  fi
  gh auth status >/dev/null 2>&1
}

# Downloads Sonada's git settings and includes them at the top of ~/.gitconfig, once. Written with cat >, not mv, so a
# ~/.gitconfig that is a symlink (a dotfiles repo) stays one.
sonada_gitconfig() {
  local tmp
  mkdir -p "$(dirname "$SONADA_GITCONFIG")" || return 1
  curl -fsSL -o "$SONADA_GITCONFIG.tmp" "$GITCONFIG_URL" || return 1
  mv "$SONADA_GITCONFIG.tmp" "$SONADA_GITCONFIG" || return 1
  if git config --global --get-all include.path 2>/dev/null | grep -qxF "$SONADA_GITCONFIG_INCLUDE"; then
    ok "Sonada git settings: updated"
    return 0
  fi
  tmp="$(mktemp)"
  { printf '[include]\n\tpath = %s\n' "$SONADA_GITCONFIG_INCLUDE"; cat "$HOME/.gitconfig" 2>/dev/null || true; } >"$tmp" &&
    cat "$tmp" >"$HOME/.gitconfig" && rm -f "$tmp" && ok "added Sonada git settings to ~/.gitconfig"
}

# Name and email for commits, and the key that signs them. Values already set are left alone.
git_identity() {
  local name email
  name="$(git config --global user.name || true)"
  if [[ -n "$name" ]]; then
    ok "git name: $name"
  else
    # gh prints an API error to stdout, so a failed call must count as no value.
    name="$(gh api user --jq '.name // empty' 2>/dev/null)" || name=""
    if [[ -z "$name" ]]; then
      printf '    Your full name for git commits (First Last): '
      read -r name <"$TTY_DEV" || true
    fi
    [[ -n "$name" ]] || { warn "no name given"; return 1; }
    git config --global user.name "$name" && ok "git name: $name"
  fi

  email="$(git config --global user.email || true)"
  if [[ -n "$email" ]]; then
    ok "git email: $email"
  else
    email="$(gh api user/emails --jq '[.[] | select(.verified and (.email | endswith("@sonada.io")))][0].email // empty' \
      2>/dev/null)" || email=""
    if [[ -z "$email" ]]; then
      warn "Your GitHub account has no verified @sonada.io email. Add it in GitHub, Settings, Emails, then run again."
      return 1
    fi
    git config --global user.email "$email" && ok "git email: $email"
  fi

  if [[ -z "$(git config --global user.signingkey || true)" ]]; then
    git config --global user.signingkey "$SSH_KEY.pub" && ok "git signs commits with $SSH_KEY.pub"
  fi
}

# An ed25519 key with a passphrase kept in the macOS Keychain, used for GitHub sign-in and for signing commits.
ssh_key() {
  local email pub title type existing out
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" || return 1
  if [[ -f "$SSH_KEY" ]]; then
    ok "SSH key: already there"
  else
    email="$(git config --global user.email || true)"
    echo "Choose a passphrase for your new SSH key. Your Mac's Keychain remembers it, so you type it only now."
    tty_run ssh-keygen -q -t ed25519 -C "${email:-sonada}" -f "$SSH_KEY" || return 1
    ok "created $SSH_KEY"
  fi
  tty_run ssh-add -q --apple-use-keychain "$SSH_KEY" || return 1

  if ! grep -qsiE '^[[:space:]]*host[[:space:]]+(.*[[:space:]])?github\.com([[:space:]]|$)' "$HOME/.ssh/config"; then
    printf '\nHost github.com\n  AddKeysToAgent yes\n  UseKeychain yes\n  IdentitiesOnly yes\n  IdentityFile %s\n' \
      "$SSH_KEY" >>"$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config" && ok "added github.com to ~/.ssh/config"
  fi

  # GitHub's host keys, read from its API over HTTPS, so the first SSH connection has nothing to trust blindly.
  touch "$HOME/.ssh/known_hosts"
  while read -r key; do
    [[ -n "$key" ]] || continue
    grep -qxF "github.com $key" "$HOME/.ssh/known_hosts" || echo "github.com $key" >>"$HOME/.ssh/known_hosts"
  done < <(gh api meta --jq '.ssh_keys[]')

  pub="$(cut -d' ' -f1,2 "$SSH_KEY.pub")"
  title="Sonada $(scutil --get ComputerName 2>/dev/null || hostname -s)"
  for type in authentication signing; do
    if [[ "$type" == authentication ]]; then
      existing="$(gh api user/keys --paginate --jq '.[].key')" || return 1
    else
      existing="$(gh api user/ssh_signing_keys --paginate --jq '.[].key')" || return 1
    fi
    if grep -qxF "$pub" <<<"$existing"; then
      ok "SSH key on GitHub ($type): already added"
    else
      gh ssh-key add "$SSH_KEY.pub" --type "$type" --title "$title" >/dev/null || return 1
      ok "added the SSH key to GitHub ($type)"
    fi
  done

  gh config set --host github.com git_protocol ssh || return 1
  # GitHub answers a working key with "successfully authenticated" and exit code 1, since it gives no shell.
  out="$(ssh -T -o BatchMode=yes git@github.com 2>&1 || true)"
  if [[ "$out" == *"successfully authenticated"* ]]; then
    ok "SSH to GitHub works"
  else
    warn "SSH to GitHub didn't work: $out"
    return 1
  fi
}

# Repos cloned over HTTPS before this script set up SSH move to SSH.
remotes_to_ssh() {
  local dir url
  for dir in "$DEST"/*/; do
    [[ -d "$dir.git" ]] || continue
    url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    if [[ "$url" =~ ^https://github\.com/(.+)$ ]]; then
      git -C "$dir" remote set-url origin "git@github.com:${BASH_REMATCH[1]}" && ok "$(basename "$dir"): origin uses SSH"
    fi
  done
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

  # ---- 2b. oh my zsh -----------------------------------------------------------
  say "oh my zsh"
  if [[ -d "$HOME/.oh-my-zsh" || (-n "${ZSH:-}" && -f "$ZSH/oh-my-zsh.sh") ]]; then
    ok "already installed"
  elif [[ "$ROLE" == "rnd" ]]; then
    try "oh my zsh" oh_my_zsh_install "$RND_OMZ_PLUGINS"
  else
    try "oh my zsh" oh_my_zsh_install "$OMZ_PLUGINS"
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

  if [[ "$ROLE" == "ops" ]]; then
    summary
    return
  fi

  # ---- 6. Developer tools (R&D) or git tools (Product) -------------------------
  if [[ "$ROLE" == "rnd" ]]; then
    say "Developer tools"
    for tap in "${TAPS[@]}"; do try "tap $tap" brew tap "$tap"; done
    install_formulae "${FORMULAE[@]}"
    install_cli_casks "${CLI_CASKS[@]}"
    if command -v npm >/dev/null && [[ "$(npm --version)" != "$NPM_VERSION".* ]]; then
      try "npm $NPM_VERSION" npm install --global "npm@$NPM_VERSION"
    fi
  else
    say "Git tools"
    install_formulae "${GIT_FORMULAE[@]}"
  fi

  # ---- 7. GitHub (R&D, Product) ------------------------------------------------
  say "GitHub"
  if ! command -v gh >/dev/null; then
    warn "gh isn't installed, so GitHub, git and SSH setup are skipped."
    FAILED+=("GitHub sign-in")
    summary
    return
  fi
  if ! github_sign_in; then
    warn "GitHub sign-in didn't finish, so git, SSH and cloning are skipped."
    FAILED+=("GitHub sign-in")
    summary
    return
  fi
  login="$(gh api user --jq .login 2>/dev/null || true)"
  if [[ -n "$login" && "$login" != *-sonada ]]; then
    warn "Signed in to GitHub as $login. Sonada accounts are named <first name>-sonada. Ask in #onboarding if that's wrong."
  fi
  # A new hire's org invite is still pending here. Accept it if GitHub matched it to this account.
  if [[ "$(gh api "user/memberships/orgs/$ORG" --jq .state 2>/dev/null || true)" == "pending" ]]; then
    gh api --method PATCH "user/memberships/orgs/$ORG" -f state=active >/dev/null && ok "accepted the $ORG invite"
  fi
  try "git credentials for GitHub" gh auth setup-git

  # ---- 8. Git and SSH (R&D, Product) -------------------------------------------
  say "Git and SSH"
  try "Sonada git settings" sonada_gitconfig
  try "git name and email" git_identity
  try "SSH key" ssh_key

  if [[ "$ROLE" != "rnd" ]]; then
    summary
    return
  fi

  # ---- 9. Repos (R&D) ----------------------------------------------------------
  say "Repos in $DEST"
  mkdir -p "$DEST"
  remotes_to_ssh
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
