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
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationService())
}
