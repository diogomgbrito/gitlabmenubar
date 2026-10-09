//
//  SettingsView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 18/12/2025.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthenticationService
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var watchedProjects: [GitLabClient.Project] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)

                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            Form {
                Section("Projects") {
                    Picker("Active projects from last", selection: $settingsManager.activeTimeMonths) {
                        ForEach(1...6, id: \.self) { months in
                            Text("\(months) month\(months > 1 ? "s" : "")").tag(months)
                        }
                    }
                }

                Section("Notifications") {
                    Toggle("Enable notifications", isOn: $settingsManager.notificationsEnabled)

                    Toggle("Review requests", isOn: $settingsManager.notifyReviewRequests)
                        .disabled(!settingsManager.notificationsEnabled)
                    Toggle("Assigned issues", isOn: $settingsManager.notifyAssignedIssues)
                        .disabled(!settingsManager.notificationsEnabled)
                    Toggle("My MR approved/merged", isOn: $settingsManager.notifyOwnMRUpdates)
                        .disabled(!settingsManager.notificationsEnabled)

                    Picker("Check every", selection: $settingsManager.pollIntervalSeconds) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("5 minutes").tag(300)
                        Text("15 minutes").tag(900)
                        Text("30 minutes").tag(1800)
                        Text("60 minutes").tag(3600)
                    }
                    .disabled(!settingsManager.notificationsEnabled)

                    if !settingsManager.watchedProjectIds.isEmpty || !settingsManager.watchedIssueKeys.isEmpty {
                        Text("Watching \(settingsManager.watchedProjectIds.count) project\(settingsManager.watchedProjectIds.count == 1 ? "" : "s") and \(settingsManager.watchedIssueKeys.count) issue\(settingsManager.watchedIssueKeys.count == 1 ? "" : "s"). Enable the bell icon on a project or issue to add more.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Open a project or issue and tap the bell icon to start watching it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Claude reviews") {
                    TextField("Repos folder", text: $settingsManager.reposRoot)
                    TextField("Claude CLI", text: $settingsManager.claudePath)

                    if watchedProjects.isEmpty {
                        Text("Watch a project (bell icon) to set up Claude reviews for it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(watchedProjects) { project in
                            claudeProjectRow(project)
                        }
                        Text("Auto: a review request starts a background Claude session in that repo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Account") {
                    Button("Logout", role: .destructive) {
                        authService.logout()
                        dismiss()
                    }
                }

                Section("Application") {
                    Button("Quit App", role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .environmentObject(settingsManager)
        .task { await loadWatchedProjects() }
    }

    @ViewBuilder
    private func claudeProjectRow(_ project: GitLabClient.Project) -> some View {
        let repo = LocalRepoResolver.shared.repo(for: project.id, pathWithNamespace: project.pathWithNamespace)
        let hasOverride = settingsManager.repoPathOverrides[String(project.id)] != nil

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                if let repo {
                    Text((repo.url.path as NSString).abbreviatingWithTildeInPath + (repo.hasReviewCommand ? "  · /review-mr" : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text("No local clone found")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button("Choose folder…") { chooseRepo(for: project) }
                if hasOverride {
                    Button("Auto-detect") {
                        settingsManager.repoPathOverrides[String(project.id)] = nil
                    }
                }
            } label: {
                Image(systemName: "folder")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Set local repo")

            Toggle("Auto", isOn: Binding(
                get: { settingsManager.autoReviewProjectIds.contains(project.id) },
                set: { _ in settingsManager.toggleAutoReview(project.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
            .help("Start a Claude review automatically when you're asked to review")
        }
    }

    private func chooseRepo(for project: GitLabClient.Project) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Local clone of \(project.pathWithNamespace)"
        panel.directoryURL = URL(fileURLWithPath: LocalRepoResolver.expand(settingsManager.reposRoot))
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            settingsManager.repoPathOverrides[String(project.id)] = url.path
        }
    }

    private func loadWatchedProjects() async {
        let watched = settingsManager.watchedProjectIds
        guard !watched.isEmpty,
              let projects = try? await GitLabClient(authService: authService).fetchStarredProjects() else { return }
        watchedProjects = projects.filter { watched.contains($0.id) }.sorted { $0.name < $1.name }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationService())
}
