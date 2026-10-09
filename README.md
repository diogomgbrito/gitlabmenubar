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

## Development

See [CLAUDE.md](CLAUDE.md) for build commands and architecture, and [RELEASING.md](RELEASING.md) for publishing a new version.
