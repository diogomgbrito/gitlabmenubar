# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GitlabMenubar is a macOS menu bar app built with SwiftUI that provides quick access to GitLab projects, issues, merge requests, and pipelines. It runs as a menu bar-only application (LSUIElement=YES) with a popover interface.

## Development Workflow

**Change → Build → Review cycle**: after every code change, build with xcodebuild and confirm success before reporting done. The user reviews the running app.

```bash
# Build (run after every change)
xcodebuild -project GitlabMenubar.xcodeproj -scheme GitlabMenubar -configuration Debug build -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"

# Relaunch after build
pkill -x GitlabMenubar; sleep 1; open /Users/diogobrito/Library/Developer/Xcode/DerivedData/GitlabMenubar-aniemhqlqbrafzayoulomrpykrte/Build/Products/Debug/GitlabMenubar.app

# Clean build
xcodebuild -project GitlabMenubar.xcodeproj -scheme GitlabMenubar clean
```

**Note**: This project requires macOS 15.5+ (MACOSX_DEPLOYMENT_TARGET = 15.5) and Xcode 16.4+.

SourceKit shows many "Cannot find X in scope" errors across files — these are cross-file false positives and do not indicate real build errors. Trust `xcodebuild` output, not SourceKit diagnostics.

## Architecture

### Three-Layer Structure

1. **Services Layer** (`GitlabMenubar/Services/`)
   - `AuthenticationService`: Manages GitLab URL configuration, keychain-based token storage, and authentication state. Published properties trigger UI updates when auth state changes.
   - `GitLabClient`: Handles all GitLab API v4 requests. Requires AuthenticationService instance for token access. All fetch methods are async/throws.
   - `SettingsManager`: Manages user preferences via UserDefaults (e.g., activeTimeMonths for filtering recent projects).

2. **Views Layer** (`GitlabMenubar/Views/`)
   - `SetupView`: Initial token entry screen (shown when not authenticated)
   - `ProjectListView`: Main view showing starred projects filtered by recent activity
   - `ProjectDetailView`: Navigation hub — custom header with back button + 3 icon tab buttons (Tasks/MRs/Pipelines); no TabView
   - `ProjectTasksView`: Displays issues with label filter chips and persistence per project
   - `ProjectMRsView`: Shows merge requests with text tab filters (Open/Merged), My MRs toggle, and NavigationLink to MRDetailView
   - `MRDetailView`: Full MR detail — status, assignees, reviewers, changes count, description (images/videos stripped with notice), linked issues resolved from both `closes_issues` API and `#N` refs parsed from title/description
   - `ProjectPipelinesView`: Lists pipelines with status dot + relative date
   - `SettingsView`: App configuration using `Form { Section }` layout

3. **App Entry & Menu Bar** (`GitlabMenubar/`)
   - `GitlabMenubarApp.swift`: SwiftUI app entry point with AppDelegate adaptor
   - `AppDelegate.swift`: Creates NSStatusItem, handles left/right click (left=popover, right=context menu)
   - `ContentView.swift`: Root view — routes to SetupView or ProjectListView, applies `.background(.ultraThinMaterial)`

### Key Patterns

- **Environment Objects**: `AuthenticationService` is injected via `.environmentObject()` and accessed with `@EnvironmentObject` in views.
- **Navigation**: Uses SwiftUI `NavigationStack` with `NavigationLink` for drill-down navigation. `ProjectDetailView` manages tab switching internally via `@State var selectedTab: Tab` enum.
- **Token Management**: Access tokens stored in macOS Keychain (service: "com.gitlabmenubar.auth"). GitLab URL stored in UserDefaults.
- **State Persistence**: Uses `@AppStorage` for per-project settings (e.g., last selected label in ProjectTasksView uses key "lastSelectedLabel_\(projectId)").
- **Menu Bar Behavior**: Right-click shows context menu with Settings and Quit. Left-click toggles popover. Popover size: **380×500**.

### UI Design Tokens

Applied consistently across all views (established in the 2026-05 UI refresh):

- **Background**: `.ultraThinMaterial` at root (frosted glass)
- **Popover size**: 380×500 (set in `AppDelegate.swift`)
- **No fixed `.frame`** on views — popover size controls dimensions
- **Typography**: `.system(size: 15, weight: .semibold)` for screen titles; `.system(size: 13, weight: .medium)` for list item titles; `.caption` for metadata; `.caption2` for tertiary
- **Horizontal padding**: 16pt consistently
- **Lists**: `.listStyle(.plain)` + `.listRowBackground(Color.clear)` + `.scrollContentBackground(.hidden)` everywhere
- **Filter tabs**: Plain `Button` with `.primary`/`.secondary` foreground + 1.5pt accentColor underline offset `y: 6`
- **Status indicators**: 5–6pt filled `Circle` inline with status text
- **Label chips**: Capsule shape, no border — selected: accentColor fill + white text; unselected: `secondary.opacity(0.12)` fill

## GitLab API Integration

All API calls go through `GitLabClient` methods:
- `fetchStarredProjects()`: Gets projects with starred=true & membership=true
- `fetchRecentActivityProjectIds(after:)`: Fetches user events for activity filtering
- `fetchProjectIssues(projectId:labels:)`: Gets opened issues, optionally filtered by labels
- `fetchProjectIssue(projectId:issueIid:)`: Gets a single issue by IID
- `fetchProjectMergeRequests(projectId:scope:reviewerId:state:)`: Fetches MRs with various filters
- `fetchMergeRequestDetail(projectId:mrIid:)`: Fetches full MR detail including description and changesCount
- `fetchMRClosesIssues(projectId:mrIid:)`: Gets issues formally linked via "Closes #N" in the MR
- `fetchProjectPipelines(projectId:status:)`: Gets recent pipelines
- `fetchProjectLabels(projectId:)`: Gets all project labels for filtering
- `validateToken()`: Checks token validity and distinguishes expired vs unauthorized errors

Error handling: `ClientError` enum with cases for invalidURL, missingToken, unauthorized, expiredToken, etc.

## Common Development Workflows

When adding new GitLab API integrations:
1. Add Codable struct to `GitLabClient` with proper `CodingKeys` for snake_case conversion
2. Create fetch method following existing async/throws pattern with error handling
3. Add view in `Views/` that uses `@EnvironmentObject var authService: AuthenticationService` to create GitLabClient instance
4. Use `@State` for loading states and fetched data

When creating new SwiftUI views:
- Add `import Inject` at the top
- Add `@ObserveInjection var inject` property to the View struct
- Add `.enableInjection()` modifier at the end of the view's body
- Follow the UI design tokens above for consistent look

When modifying authentication:
- Token changes must update `AuthenticationService.isAuthenticated` to trigger UI refresh
- All token operations happen through AuthenticationService (never access keychain directly elsewhere)

## Entitlements

The app requires `GitlabMenubar/GitlabMenubar.entitlements` with keychain access groups configured for secure token storage.
