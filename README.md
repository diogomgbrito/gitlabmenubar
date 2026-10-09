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

## AI reviews

When you're asked to review an MR, GitlabMenubar can start the review for you in a coding agent: [Claude Code](https://claude.com/claude-code), [opencode](https://opencode.ai) or [Codex](https://developers.openai.com/codex). The review runs in the background in your local clone of the project, and you open the session when it's done.

- **Review with <agent>** starts the review. The arrow next to it picks another agent for that MR.
- **Re-run review** appears once the MR has a session: it runs the review again **in the same session**, so the agent knows what it reviewed before.
- **Open session** opens it in Terminal (`claude attach`, `opencode -s <id>`, `codex resume <id>`). While the agent is working, the MR shows "Reviewing…".
- **Copy prompt** copies the prompt to paste yourself — `@<repo> /review-mr <iid>` for `claude agents`, the full review prompt for the others.
- **Auto-review** (per project, in Settings) starts the review as soon as the review request arrives.

The buttons are on the Reviews list, the MR detail and the review-request notification.

### Setup — Settings → AI reviews

1. **Default agent**, and per project in the **⋯** menu.
2. **Repos folder**: where your clones live (default `~/brilean/git`). Each project is matched to its clone by the git `origin` remote; **⋯ → Choose repo folder…** picks one manually.
3. **CLI path** (and model, for opencode/Codex) of the agents you use. Found automatically in the usual install locations and your shell's PATH.
4. Claude only: run `claude` once in each repo and accept the trust prompt — background sessions only start in trusted folders.

### The review command

Repos with `.claude/commands/review-mr.md` use it with every agent:

- **Claude Code** runs `/review-mr <iid>`.
- **opencode** gets a copy in `.opencode/commands/review-mr.md`, **Codex** a skill in `.agents/skills/review-mr/SKILL.md`, so you can re-run it in a resumed session. Copies are git-excluded, refreshed when the Claude command changes, and look up the project from the repo's git remote. Remove the `generated-by` line to keep your own edited version.

Other repos get a generic review prompt that reads the MR with `glab`.

Background runs with opencode and Codex don't post anything to GitLab: you resume the session, read the review and confirm what to post — like `/review-mr` does in Claude.

### Permissions: let the agent run `glab`

Reading the MR and posting the review run `glab`, which needs shell access **with network**. Check your agent's mode:

| Agent | Default | What to do |
|---|---|---|
| Claude Code | `auto` mode — `glab` runs | Nothing. In a stricter mode, allow `Bash(glab:*)`. |
| opencode | Everything allowed, no sandbox — `glab` runs | Nothing, unless your config restricts `shell`: then allow `glab *`. |
| Codex | `workspace-write` sandbox with **network off** — `glab` fails | In `~/.codex/config.toml` set `[sandbox_workspace_write]` → `network_access = true`. On macOS this may not be enough; then start with `--sandbox danger-full-access` (no sandbox — use with care). |

The app's own background Codex runs use a read-only sandbox on purpose: GitlabMenubar fetches the MR with `glab` first and puts it in the prompt, so Codex doesn't need the network until you resume the session to post.

## Development

See [CLAUDE.md](CLAUDE.md) for build commands and architecture, and [RELEASING.md](RELEASING.md) for publishing a new version.
