//
//  UpdateBanner.swift
//  GitlabMenubar
//

import SwiftUI

/// Home-page notice for a newer release: update through Homebrew, copy the command, or dismiss.
struct UpdateBanner: View {
    @ObservedObject private var updates = UpdateService.shared
    @State private var copied = false

    var body: some View {
        if updates.showsBanner, let version = updates.availableVersion {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Button("Version \(version) is available") {
                    UpdateWindowController.shared.show()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .lineLimit(1)
                .help("Show what's new")

                Spacer(minLength: 4)

                UpdateButtons(copied: $copied)
                    .controlSize(.small)

                Button {
                    updates.skip()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Skip this version")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }
}

/// "Update" (background brew upgrade, progress in the update window; release page without Homebrew)
/// + "Copy command".
struct UpdateButtons: View {
    @ObservedObject private var updates = UpdateService.shared
    @Binding var copied: Bool

    var body: some View {
        HStack(spacing: 6) {
            if updates.isUpdating {
                ProgressView()
                    .controlSize(.small)
                Text("Updating…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(updates.brewURL == nil ? "Download" : "Update") {
                    updates.upgrade()
                    if updates.brewURL != nil { UpdateWindowController.shared.show() }
                }
                .help(updates.brewURL == nil ? "Open the release page" : "Install with Homebrew and restart")
            }

            if updates.brewURL != nil {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(UpdateService.upgradeCommand, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .help("Copy \(UpdateService.upgradeCommand)")
            }
        }
    }
}
