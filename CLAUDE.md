# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working w/ code in this repo.

## Project Overview

GitlabMenubar is macOS menu bar app built w/ SwiftUI that provides quick access to GitLab projects, issues, merge requests, and pipelines. It runs as menu bar-only application (LSUIElement=YES) w/ popover interface.

## Development Workflow

**Change → Build → Review cycle**: after every code change, build w/ xcodebuild and confirm success before reporting done. user reviews running app.

```bash
# Build (run after every change)
xcodebuild -project GitlabMenubar.xcodeproj -scheme GitlabMenubar -configuration Debug build -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" 2>&1 | grep -E "error:|BUILD"

# Relaunch after build
pkill -x GitlabMenubar; sleep 1; open /Users/diogobrito/Library/Developer/Xcode/DerivedData/GitlabMenubar-brudpbgtdgfabfehvdkfxhlbzdup/Build/Products/Debug/GitlabMenubar.app

# Clean build
xcodebuild -project GitlabMenubar.xcodeproj -scheme GitlabMenubar clean
```

**Signing**: no Apple certificates on this machine — builds are ad-hoc signed (`CODE_SIGN_IDENTITY="-"`). Releases: see `RELEASING.md`.

**Note**: This project requires macOS 15.5+ (MACOSX_DEPLOYMENT_TARGET = 15.5) and Xcode 16.4+.

SourceKit shows many "Cannot find X in scope" errors across files — these are cross-file false positives and do not indicate real build errors. Trust `xcodebuild` output, not SourceKit diagnostics.

## Architecture

### Three-Layer Structure

1. **Services Layer** (`GitlabMenubar/Services/`)
   - `AuthenticationService`Manages GitLab URL config, keychain-based token storage, and authentication state. Published properties trigger UI updates when auth state changes.
   - `GitLabClient`Handles all GitLab API v4 requests. Requires AuthenticationService instance for token access. All fetch methods are async/throws.
   - `SettingsManager`Manages user preferences via UserDefaults (e.g., activeTimeMonths for filtering recent projects).
   - `NotificationService`Polls watched projects and posts notifications. Review requests get "Start review" / "Copy prompt" actions, or auto-start a review when enabled for the project.
   - `LocalRepoResolver`Maps a GitLab project to its local clone by matching `.git/config` origin against `path_with_namespace` under the repos folder (default `~/brilean/git`), w/ per-project overrides. Detects `.claude/commands/review-mr.md`.
   - `ReviewSessionService`Runs MR reviews w/ a CLI agent (`ReviewAgent`: Claude Code, opencode or Codex; per-project choice, default in Settings). Claude: `claude --bg -n "Review <project> !<iid>" "/review-mr <iid>"`, tracked via `claude agents --json` by name, opened w/ `claude attach`. opencode: detached `opencode run --format json --title …` (log in ~/Library/Logs/GitlabMenubar), session id from first JSON event stored in UserDefaults, "working" = process alive, opened w/ `opencode -s <id>` in the repo. Codex: detached `codex exec --json -s read-only -C <repo>` (session id = `thread.started.thread_id`; no network in its sandbox, so the MR data must be in the prompt), continued w/ `exec … resume <id>`, opened w/ `codex resume <id> -C <repo>`. Re-running a review continues the MR's existing session (Claude: `stop` if alive, then `--bg --resume <sessionId>`; opencode `run -s`; Codex `exec resume`). Background non-Claude runs get an instruction not to write to GitLab until resumed.
   - `AgentCommandSync`Keeps a converted copy of `.claude/commands/review-mr.md` for other agents (opencode command `.opencode/commands/review-mr.md`; Codex skill `.agents/skills/review-mr/SKILL.md` w/ `` !`cmd` `` → "run `cmd`"; project-agnostic: `glab -R <path>` → `-R "$(git remote get-url origin)"` plus a "Step 0 — Repository" section, marked `generated-by: GitlabMenubar (format N)` — bump `formatVersion` when changing the conversion, git-excluded via `.git/info/exclude`, refreshed when the Claude original changes). A user-written command (no marker) is never touched.
   - `CommandExpander`Expands the agent's `review-mr` command file into a plain prompt for headless runs (opencode v2 `run` has no `--command`) (strip frontmatter, `$ARGUMENTS`, run `` !`cmd` `` in the repo).
   - `SandboxMigration`One-time copy of UserDefaults from the old sandbox container (app was sandboxed up to 1.0.0).

2. **Views Layer** (`GitlabMenubar/Views/`)
   - `SetupView`Initial token entry screen (shown when not authenticated)
   - `ProjectListView`Main view showing starred projects filtered by recent activity
   - `ProjectDetailView`Navigation hub — custom header w/ back button + 3 icon tab buttons (Tasks/MRs/Pipelines); no TabView
   - `ProjectTasksView`Displays issues w/ label filter chips and persistence per project
   - `ProjectMRsView`Shows merge requests w/ text tab filters (Open/Merged), My MRs toggle, and NavigationLink to MRDetailView
   - `MRDetailView`Full MR detail — status, assignees, reviewers, changes count, description (images/videos stripped w/ notice), linked issues resolved from both `closes_issues` API `#N` refs parsed from title/description
   - `ProjectPipelinesView`Lists pipelines w/ status dot + relative date
   - `ReviewsView`MRs awaiting your review / changed since your review, w/ Claude review controls per row
   - `ReviewControls`Shared "Review with <agent>" (menu: other agents) / "Open session" + "Copy prompt" buttons (compact for rows, full for MR detail) and `ReviewSessionBadge`
   - `SettingsView`App config using `Form { Section }` layout

3. **App Entry & Menu Bar** (`GitlabMenubar/`)
   - `GitlabMenubarApp.swift`SwiftUI app entry point w/ AppDelegate adaptor
   - `AppDelegate.swift`Creates NSStatusItem, handles left/right click (left=popover, right=context menu)
   - `ContentView.swift`Root view — routes to SetupView or ProjectListView, applies `.background(.ultraThinMaterial)`

### Key Patterns

- **Environment Objects**: `AuthenticationService` is injected via `.environmentObject()` and accessed w/ `@EnvironmentObject` in views.
- **Navigation**: Uses SwiftUI `NavigationStack` w/ `NavigationLink` for drill-down navigation. `ProjectDetailView` manages tab switching internally via `@State var selectedTab: Tab` enum.
- **Token Management**: Access tokens stored in macOS Keychain (service: "com.gitlabmenubar.auth"). GitLab URL stored in UserDefaults.
- **State Persistence**: Uses `@AppStorage` for per-project settings (e.g., last selected label in ProjectTasksView uses key "lastSelectedLabel_\(projectId)").
- **Menu Bar Behavior**: Right-click shows context menu w/ Settings and Quit. Left-click toggles popover. Popover size: **380×500**.

### UI Design Tokens

Applied consistently across all views (established in 2026-05 UI refresh):

- **Background**: `.ultraThinMaterial` at root (frosted glass)
- **Popover size**: 380×500 (set in `AppDelegate.swift`)
- **No fixed `.frame`** on views — popover size controls dimensions
- **Typography**: `.system(size: 15, weight: .semibold)` for screen titles; `.system(size: 13, weight: .medium)` for list item titles; `.caption` for metadata; `.caption2` for tertiary
- **Horizontal padding**: 16pt consistently
- **Lists**: `.listStyle(.plain)` + `.listRowBackground(Color.clear)` + `.scrollContentBackground(.hidden)` everywhere
- **Filter tabs**: Plain `Button` w/ `.primary`/`.secondary` foreground + 1.5pt accentColor underline offset `y: 6`
- **Status indicators**: 5–6pt filled `Circle` inline w/ status text
- **Label chips**: Capsule shape, no border — selected: accentColor fill + white text; unselected: `secondary.opacity(0.12)` fill

## GitLab API Integration

All API calls go through `GitLabClient` methods:
- `fetchStarredProjects()`Gets projects w/ starred=true & membership=true
- `fetchRecentActivityProjectIds(after:)`Fetches user events for activity filtering
- `fetchProjectIssues(projectId:labels:)`Gets opened issues, optionally filtered by labels
- `fetchProjectIssue(projectId:issueIid:)`Gets single issue by IID
- `fetchProjectMergeRequests(projectId:scope:reviewerId:state:)`Fetches MRs w/ various filters
- `fetchMergeRequestDetail(projectId:mrIid:)`Fetches full MR detail including description and changesCount
- `fetchMRClosesIssues(projectId:mrIid:)`Gets issues formally linked via "Closes #N" in MR
- `fetchProjectPipelines(projectId:status:)`Gets recent pipelines
- `requestReReview(projectPath:mrIid:userId:)`GraphQL `mergeRequestReviewerRereview` (no REST equivalent); shown per reviewer in `MRDetailView` when you are the MR author/assignee
- `fetchPendingReviewTodos()`Pending `review_requested` to-dos; `NotificationService` treats a new one for an already-seen review MR as a re-request
- `fetchProjectLabels(projectId:)`Gets all project labels for filtering
- `validateToken()`Checks token validity and distinguishes expired vs unauthorized errors

Error handling: `ClientError` enum w/ cases for invalidURL, missingToken, unauthorized, expiredToken, etc.

## Common Development Workflows

When adding new GitLab API integrations:
1. Add Codable struct to `GitLabClient` w/ proper `CodingKeys` for snake_case conversion
2. Create fetch method following existing async/throws pattern w/ error handling
3. Add view in `Views/` that uses `@EnvironmentObject var authService: AuthenticationService` to create GitLabClient instance
4. Use `@State` for loading states and fetched data

When creating new SwiftUI views:
- Add `import Inject` at top
- Add `@ObserveInjection var inject` property to View struct
- Add `.enableInjection()` modifier at end of view's body
- Follow UI design tokens above for consistent look

When modifying authentication:
- Token changes must update `AuthenticationService.isAuthenticated` to trigger UI refresh
- All token operations happen through AuthenticationService (never access keychain directly elsewhere)

## Entitlements

Not sandboxed (since 1.1): needs to run the `claude` CLI and read local repos. `GitlabMenubar/GitlabMenubar.entitlements` only declares `network.client`.

