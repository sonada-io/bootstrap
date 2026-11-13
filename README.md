# bootstrap

Sets up a Sonada laptop (macOS). Run in Terminal, with your role (`rnd`, `product` or `ops`):

```bash
curl -fsSL https://raw.githubusercontent.com/sonada-io/bootstrap/main/bootstrap.sh | bash -s -- --role rnd
```

Everyone gets:

- the Xcode command line tools and Homebrew
- the Chrome, Claude, ChatGPT, Slack and Notion apps
- Claude Code, and a Claude sign-in
- [Mila](https://github.com/island-io/mila) (macOS 14 or later), with Sonada's settings from `sonada.milaconfig` (Mila shows the changes and asks before applying them) and its MCP server added to Claude Desktop and Claude Code

R&D also gets Docker Desktop, git, gh, uv, Node with npm 11.19, Python 3.15, the AWS CLI and Terraform. Then it signs you in to GitHub and clones `demo` and `skills` into `~/sonada-io`.

Mila is installed only when its download passes Apple's signature and notarization checks and is signed by the Team ID in `MILA_TEAM_ID`.

Mila's access for Claude stays off until you turn it on in Mila (Settings ▸ Storage). That switch is your consent, so the script never flips it.

It is safe to run again, for example on a new laptop: it skips anything already installed. To change what gets installed, edit the lists at the top of `bootstrap.sh` (or `sonada.milaconfig`) and open a PR.

This repo is public on purpose, so the command works before you have GitHub access. It holds no secrets.
