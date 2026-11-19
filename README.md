# bootstrap

Sets up a Sonada laptop (macOS). Run in Terminal, with your role (`rnd`, `product` or `ops`):

```bash
curl -fsSL https://raw.githubusercontent.com/sonada-io/bootstrap/main/bootstrap.sh | bash -s -- --role rnd
```

Everyone gets:

- the Xcode command line tools and Homebrew
- [oh my zsh](https://ohmyz.sh), with the `git` and `gh` plugins (an existing `~/.zshrc` moves to `~/.zshrc.pre-oh-my-zsh` and the new one loads it, so your own settings keep working)
- the Chrome, Claude, ChatGPT, Slack and Notion apps
- Claude Code, and a Claude sign-in
- [Mila](https://github.com/island-io/mila) (macOS 14 or later), with Sonada's settings from `sonada.milaconfig` (Mila shows the changes and asks before applying them) and its MCP server added to Claude Desktop and Claude Code

R&D and Product also get git and gh, a GitHub sign-in, Sonada's git settings and an SSH key (see below).

R&D also gets Docker Desktop, uv, Node with npm 11.19, Python 3.15, the AWS CLI, the Google Cloud CLI (`gcloud`) and Terraform, the `aws` and `gcloud` oh my zsh plugins, and clones `demo` and `skills` into `~/sonada-io` over SSH. The AWS and Google Cloud CLIs are installed only: sign in to them when you need them.

## Git and SSH (R&D, Product)

- **GitHub account.** Create a new one from the sonada-io invite in your Sonada inbox, with your Sonada email, named `<first name>-sonada` (lowercase), or `<first name>-<last name>-sonada` if that's taken. If the signed-in account isn't named that way, the script skips git, SSH and cloning, and says how to fix it: rename the account (GitHub, Settings, Account, Change username), or `gh auth logout --hostname github.com` if you signed in with a personal one. Then run the command again.
- **Git settings.** `sonada.gitconfig` (aliases like `git st` and `git lg`, `push.autoSetupRemote`, `pull.rebase`) is copied to `~/.config/sonada/gitconfig` on every run and included at the top of `~/.gitconfig`, so your own settings there win. Change it with a PR: everyone gets it on their next run.
- **Identity.** `user.name` from your GitHub profile (or it asks), `user.email` from the verified `@sonada.io` email on your GitHub account. Values already in `~/.gitconfig` are kept.
- **SSH key.** `~/.ssh/id_ed25519_sonada`, with a passphrase kept in the macOS Keychain. It is added to GitHub twice, for sign-in and for signing. Commit and tag signing is turned on in `~/.gitconfig` only after that, and a signing key you already set (GPG or your own SSH key) is kept. git and gh switch to SSH only when SSH reaches GitHub as your signed-in account, otherwise they stay on HTTPS. A new laptop gets its own key. Remove an old laptop's keys in GitHub, Settings, SSH and GPG keys.

Mila is installed only when its download passes Apple's signature and notarization checks and is signed by the Team ID in `MILA_TEAM_ID`.

Mila's access for Claude stays off until you turn it on in Mila (Settings ▸ Storage). That switch is your consent, so the script never flips it.

It is safe to run again, for example on a new laptop: it skips anything already installed. To change what gets installed, edit the lists at the top of `bootstrap.sh` (or `sonada.milaconfig`) and open a PR.

This repo is public on purpose, so the command works before you have GitHub access. It holds no secrets.
