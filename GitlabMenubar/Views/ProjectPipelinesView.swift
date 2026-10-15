//
//  ProjectPipelinesView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 17/12/2025.
//

import SwiftUI

struct ProjectPipelinesView: View {
    let project: GitLabClient.Project
    var reloadToken = 0
    @EnvironmentObject var authService: AuthenticationService

    @State private var pipelines: [GitLabClient.Pipeline] = []
    @State private var isLoadingPipelines = false
    @State private var pipelineError: String?
    @State private var pipelineEmptyMessage: String = "No pipelines found"

    var body: some View {
        Group {
            if isLoadingPipelines && pipelines.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = pipelineError {
                VStack(spacing: 8) {
                    Text("Error loading pipelines")
                        .font(.system(size: 13, weight: .medium))
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await loadPipelines() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if pipelines.isEmpty {
                Text(pipelineEmptyMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                List(pipelines) { pipeline in
                    let statusColor: Color = {
                        switch pipeline.status {
                        case "success": return .green
                        case "running": return .blue
                        case "failed": return .red
                        case "canceled": return .secondary
                        case "skipped": return .gray
                        case "running_with_warnings", "success_with_warnings": return .yellow
                        default: return .primary
                        }
                    }()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("#\(pipeline.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(pipeline.ref)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }

                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 5, height: 5)
                            Text(pipeline.status.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(relativeDate(pipeline.updatedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = URL(string: pipeline.webUrl) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task {
            if pipelines.isEmpty {
                await loadPipelines()
            }
        }
        .onChange(of: reloadToken) {
            Task { await loadPipelines() }
        }
    }

    private func relativeDate(_ isoString: String) -> String {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = withFractional.date(from: isoString) ?? plain.date(from: isoString) else {
            return isoString
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadPipelines() async {
        isLoadingPipelines = true
        pipelineError = nil
        let client = GitLabClient(authService: authService)

        do {
            async let runningTask = client.fetchProjectPipelines(projectId: project.id, status: "running")
            async let failedTask = client.fetchProjectPipelines(projectId: project.id, status: "failed")

            let (runningPipelines, failedPipelines) = try await (runningTask, failedTask)

            let cutoff = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]

            let recentFailed = failedPipelines.filter { pipeline in
                if let date = withFractional.date(from: pipeline.updatedAt) ?? plain.date(from: pipeline.updatedAt) {
                    return date > cutoff
                }
                return false
            }

            let combined = (runningPipelines + recentFailed).sorted { $0.id > $1.id }

            await MainActor.run { self.pipelines = combined }

            if combined.isEmpty {
                let anyPipelines = try await client.fetchProjectPipelines(projectId: project.id, status: nil)
                await MainActor.run {
                    self.pipelineEmptyMessage = anyPipelines.isEmpty
                        ? "No pipelines found for this project"
                        : "No active or recently failed pipelines"
                    self.isLoadingPipelines = false
                }
            } else {
                await MainActor.run { self.isLoadingPipelines = false }
            }
        } catch {
            await MainActor.run {
                self.pipelineError = error.localizedDescription
                self.isLoadingPipelines = false
            }
        }
    }
}
