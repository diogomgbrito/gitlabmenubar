# GitlabMenubar

macOS menu bar app for quick access to your GitLab projects, issues, merge requests, pipelines and review requests.

## Install

Requires macOS 15 (Sequoia) or later.

```bash
brew tap diogomgbrito/gitlabmenubar https://github.com/diogomgbrito/gitlabmenubar
brew trust diogomgbrito/gitlabmenubar
brew install --cask gitlab-menubar
```

Update with `brew upgrade --cask gitlab-menubar`.

On first launch, enter your GitLab URL and a personal access token with the `api` scope. The app lives in the menu bar: left-click opens it, right-click shows Settings and Quit.

> The app is not notarized by Apple. The Homebrew cask removes the quarantine flag so macOS lets it open. After an upgrade, macOS may ask once for keychain access — choose "Always Allow".

## Claude reviews

When you're asked to review an MR, GitlabMenubar can start the review in [Claude Code](https://claude.com/claude-code) for you.

- **Review with Claude** starts a background session in your local clone of the project — the same as typing `@<repo> /review-mr <iid>` in `claude agents`. It shows up in your `claude agents` list.
- **Copy prompt** copies `@<repo> /review-mr <iid>` to paste into `claude agents` yourself.
- Once a session is running, the MR shows "Reviewing…" and the button becomes **Open session** (`claude attach` in Terminal).
- **Auto-review** (per project, in Settings) starts the session as soon as the review request arrives.

The buttons are on the Reviews list, the MR detail and the review-request notification.

Setup, in **Settings → Claude reviews**:

1. **Repos folder**: where your clones live (default `~/brilean/git`). Each project is matched to its clone by the git `origin` remote. Use the folder button to pick a clone manually.
2. **Claude CLI**: path to `claude` (default `~/.local/bin/claude`).
3. Run `claude` once in each repo and accept the trust prompt — background sessions only start in trusted folders.

Repos with a `.claude/commands/review-mr.md` command use `/review-mr <iid>`. Other repos get a generic review prompt that reads the MR with `glab`.

## Development

See [CLAUDE.md](CLAUDE.md) for build commands and architecture, and [RELEASING.md](RELEASING.md) for publishing a new version.
