//
//  ProjectDetailView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 16/12/2025.
//

import SwiftUI

struct ProjectDetailView: View {
    let project: GitLabClient.Project
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settingsManager = SettingsManager.shared

    enum Tab {
        case tasks, mrs, pipelines

        var webPath: String {
            switch self {
            case .tasks: return "issues"
            case .mrs: return "merge_requests"
            case .pipelines: return "pipelines"
            }
        }
    }

    @State private var selectedTab: Tab = .tasks
    /// Bumped by ⌘R; the selected tab reloads when it changes.
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon tab buttons
            HStack(spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)

                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        settingsManager.toggleProjectWatch(project.id)
                        NotificationService.shared.pollNow()
                    } label: {
                        Image(systemName: settingsManager.isProjectWatched(project.id) ? "bell.fill" : "bell")
                            .font(.system(size: 13))
                            .foregroundStyle(settingsManager.isProjectWatched(project.id) ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(settingsManager.isProjectWatched(project.id) ? "Notifications on for this project" : "Notify me about this project")

                    tabButton(.tasks, icon: "checklist", key: "1")
                    tabButton(.mrs, icon: "arrow.triangle.pull", key: "2")
                    tabButton(.pipelines, icon: "hammer", key: "3")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Tab content
            switch selectedTab {
            case .tasks:
                ProjectTasksView(project: project, reloadToken: reloadToken)
            case .mrs:
                ProjectMRsView(project: project, reloadToken: reloadToken)
            case .pipelines:
                ProjectPipelinesView(project: project, reloadToken: reloadToken)
            }
        }
        .navigationBarBackButtonHidden(true)
        .backShortcuts()
        .shortcut("r") { reloadToken += 1 }
        .shortcut("o") {
            if let url = URL(string: "\(project.webUrl)/-/\(selectedTab.webPath)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: Tab, icon: String, key: KeyEquivalent) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
    }
}

#Preview {
    ProjectDetailView(project: GitLabClient.Project(id: 1, name: "Test Project", pathWithNamespace: "group/test-project", starCount: 10, webUrl: "https://gitlab.com/group/test-project", avatarUrl: nil))
        .environmentObject(AuthenticationService())
}
