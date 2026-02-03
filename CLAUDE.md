# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GitlabMenubar is a macOS menu bar app built with SwiftUI that provides quick access to GitLab projects, issues, merge requests, and pipelines. It runs as a menu bar-only application (LSUIElement=YES) with a popover interface.

## Build & Run Commands

```bash
# Build the project
xcodebuild -project GitlabMenubar.xcodeproj -scheme GitlabMenubar build

# Build and run (from Xcode)
# Open GitlabMenubar.xcodeproj in Xcode and press Cmd+R

# Clean build
xcodebuild -project GitlabMenubar.xcodeproj -scheme GitlabMenubar clean
```

**Note**: This project requires macOS 15.5+ (MACOSX_DEPLOYMENT_TARGET = 15.5) and Xcode 16.4+.

## Hot Reload Development

This project is configured with the **Inject** library for SwiftUI hot reload during development:

- All SwiftUI views include `@ObserveInjection var inject` and `.enableInjection()`
- Requires **InjectionIII.app** running in the background (download from https://github.com/johnno1962/InjectionIII/releases)
- Debug build settings include `-Xlinker -interposable` linker flag
- Edit any SwiftUI view and save (Cmd+S) to see changes instantly without rebuilding

**Setup**: See `HOT_RELOAD_SETUP.md` for complete setup instructions if not already configured.

**Benefits**:
- Instant UI feedback without recompiling
- Preserves app state between code injections
- Perfect for iterating on menu bar UI/UX
- Only active in Debug builds (no performance impact in Release)

## Architecture

### Three-Layer Structure

1. **Services Layer** (`GitlabMenubar/Services/`)
   - `AuthenticationService`: Manages GitLab URL configuration, keychain-based token storage, and authentication state. Published properties trigger UI updates when auth state changes.
   - `GitLabClient`: Handles all GitLab API v4 requests. Requires AuthenticationService instance for token access. All fetch methods are async/throws.
   - `SettingsManager`: Manages user preferences via UserDefaults (e.g., activeTimeMonths for filtering recent projects).

2. **Views Layer** (`GitlabMenubar/Views/`)
   - `SetupView`: Initial token entry screen (shown when not authenticated)
   - `ProjectListView`: Main view showing starred projects filtered by recent activity
   - `ProjectDetailView`: Navigation hub for project details (tasks, MRs, pipelines)
   - `ProjectTasksView`: Displays issues with label filtering and persistence per project
   - `ProjectMRsView`: Shows merge requests with filtering (created by me, assigned to me, review requests)
   - `ProjectPipelinesView`: Lists pipelines with status filtering
   - `SettingsView`: App configuration

3. **App Entry & Menu Bar** (`GitlabMenubar/`)
   - `GitlabMenubarApp.swift`: SwiftUI app entry point with AppDelegate adaptor
   - `AppDelegate.swift`: Creates NSStatusItem, handles left/right click (left=popover, right=context menu)
   - `ContentView.swift`: Root view that routes to SetupView or ProjectListView based on auth state

### Key Patterns

- **Environment Objects**: `AuthenticationService` is injected via `.environmentObject()` and accessed with `@EnvironmentObject` in views.
- **Navigation**: Uses SwiftUI `NavigationStack` with `NavigationLink` for drill-down navigation.
- **Token Management**: Access tokens stored in macOS Keychain (service: "com.gitlabmenubar.auth"). GitLab URL stored in UserDefaults.
- **State Persistence**: Uses `@AppStorage` for per-project settings (e.g., last selected label in ProjectTasksView uses key "lastSelectedLabel_\(projectId)").
- **Menu Bar Behavior**: Right-click shows context menu with Settings and Quit. Left-click toggles popover. Popover size: 350x450.

## GitLab API Integration

All API calls go through `GitLabClient` methods:
- `fetchStarredProjects()`: Gets projects with starred=true & membership=true
- `fetchRecentActivityProjectIds(after:)`: Fetches user events for activity filtering
- `fetchProjectIssues(projectId:labels:)`: Gets opened issues, optionally filtered by labels
- `fetchProjectMergeRequests(projectId:scope:reviewerId:state:)`: Fetches MRs with various filters
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
- This enables hot reload for instant UI feedback during development

When modifying authentication:
- Token changes must update `AuthenticationService.isAuthenticated` to trigger UI refresh
- All token operations happen through AuthenticationService (never access keychain directly elsewhere)

## Entitlements

The app requires `GitlabMenubar/GitlabMenubar.entitlements` with keychain access groups configured for secure token storage.
