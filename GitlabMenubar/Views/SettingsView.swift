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
    @StateObject private var settingsManager = SettingsManager()

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
