# bootstrap

Sets up a Sonada R&D laptop (macOS). Run in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/sonada-io/bootstrap/main/bootstrap.sh | bash
```

It installs the Xcode command line tools, Homebrew, the Chrome, Claude, ChatGPT, Slack, Notion and Docker Desktop apps, git, gh, uv, Node with npm 11.19, Python 3.15, the AWS CLI and Terraform. Then it signs you in to GitHub and clones `demo` and `skills` into `~/sonada-io`.

It is safe to run again, for example on a new laptop: it skips anything already installed. To change what gets installed, edit the lists at the top of `bootstrap.sh` and open a PR.

This repo is public on purpose, so the command works before you have GitHub access. It holds no secrets.
