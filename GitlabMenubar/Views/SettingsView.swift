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

                Section("AI reviews") {
                    Picker("Default agent", selection: $settingsManager.defaultReviewAgent) {
                        ForEach(ReviewAgent.allCases) { agent in
                            Text(agent.displayName).tag(agent.rawValue)
                        }
                    }
                    TextField("Repos folder", text: $settingsManager.reposRoot)
                    if agentsInUse.contains(.claude) {
                        TextField("Claude CLI", text: $settingsManager.claudePath)
                    }
                    if agentsInUse.contains(.opencode) {
                        TextField("opencode CLI", text: $settingsManager.opencodePath)
                        TextField("opencode model", text: $settingsManager.opencodeModel, prompt: Text("default"))
                    }
                    if agentsInUse.contains(.codex) {
                        TextField("Codex CLI", text: $settingsManager.codexPath)
                        TextField("Codex model", text: $settingsManager.codexModel, prompt: Text("default"))
                    }
                    Text(permissionsHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if watchedProjects.isEmpty {
                        Text("Watch a project (bell icon) to set up AI reviews for it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(watchedProjects) { project in
                            reviewProjectRow(project)
                        }
                        Text("Auto-review: a review request starts a background review session in that repo, with the project's agent. ⋯ sets the agent and repo folder.")
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
    private func reviewProjectRow(_ project: GitLabClient.Project) -> some View {
        let repo = LocalRepoResolver.shared.repo(for: project.id, pathWithNamespace: project.pathWithNamespace)
        let hasOverride = settingsManager.repoPathOverrides[String(project.id)] != nil

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                if let repo {
                    Text((repo.url.path as NSString).abbreviatingWithTildeInPath + (repo.hasReviewCommand ? "  · /review-mr" : "") + (settingsManager.projectReviewAgents[String(project.id)].flatMap(ReviewAgent.init(rawValue:)).map { "  · \($0.displayName)" } ?? ""))
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

            HStack(spacing: 6) {
                Text("Auto-review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Auto-review", isOn: Binding(
                    get: { settingsManager.autoReviewProjectIds.contains(project.id) },
                    set: { _ in settingsManager.toggleAutoReview(project.id) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .fixedSize()
            .help("Start a review automatically when you're asked to review an MR in this project")

            Menu {
                Picker("Agent", selection: agentBinding(for: project)) {
                    Text("Default (\(ReviewAgent(rawValue: settingsManager.defaultReviewAgent)?.displayName ?? "Claude Code"))").tag("")
                    ForEach(ReviewAgent.allCases) { agent in
                        Text(agent.displayName).tag(agent.rawValue)
                    }
                }
                Divider()
                Button("Choose repo folder…") { chooseRepo(for: project) }
                if hasOverride {
                    Button("Auto-detect repo") {
                        settingsManager.repoPathOverrides[String(project.id)] = nil
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Agent and local repo")
        }
    }

    /// Reviews run `glab`, which needs shell + network permission in the agent.
    private var permissionsHint: String {
        var lines = ["Agents need permission to run glab (shell with network) to read and post reviews."]
        if agentsInUse.contains(.claude) { lines.append("Claude Code: auto mode works; otherwise allow Bash(glab:*).") }
        if agentsInUse.contains(.opencode) { lines.append("opencode: allowed by default, unless your config restricts shell.") }
        if agentsInUse.contains(.codex) {
            lines.append("Codex: network is off by default — set network_access = true under [sandbox_workspace_write] in ~/.codex/config.toml, or use --sandbox danger-full-access.")
        }
        return lines.joined(separator: "\n")
    }

    /// Agents used by the default or by any project — only their CLI settings are shown.
    private var agentsInUse: Set<ReviewAgent> {
        var agents: Set<ReviewAgent> = [ReviewAgent(rawValue: settingsManager.defaultReviewAgent) ?? .claude]
        for raw in settingsManager.projectReviewAgents.values {
            if let agent = ReviewAgent(rawValue: raw) { agents.insert(agent) }
        }
        return agents
    }

    private func agentBinding(for project: GitLabClient.Project) -> Binding<String> {
        Binding(
            get: { settingsManager.projectReviewAgents[String(project.id)] ?? "" },
            set: { settingsManager.projectReviewAgents[String(project.id)] = $0.isEmpty ? nil : $0 }
        )
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
