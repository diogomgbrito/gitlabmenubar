//
//  ProjectPipelinesView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 17/12/2025.
//

import SwiftUI

struct ProjectPipelinesView: View {
    let project: GitLabClient.Project
    @EnvironmentObject var authService: AuthenticationService

    @State private var pipelines: [GitLabClient.Pipeline] = []
    @State private var isLoadingPipelines = false
    @State private var pipelineError: String?
    @State private var pipelineEmptyMessage: String = "No pipelines found"
    
    var body: some View {
        Group {
            if isLoadingPipelines && pipelines.isEmpty {
                ProgressView()
            } else if let error = pipelineError {
                VStack {
                    Text("Error loading pipelines")
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await loadPipelines() }
                    }
                }
            } else if pipelines.isEmpty {
                VStack(spacing: 8) {
                    Text(pipelineEmptyMessage)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                List(pipelines) { pipeline in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("#\(pipeline.id)")
                                    .font(.headline)
                                Text(pipeline.ref)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            let statusColor: Color = {
                                switch pipeline.status {
                                case "success": return .green
                                case "running": return .blue
                                case "failed": return .red
                                case "canceled": return .secondary
                                case "skipped": return .gray
                                case "running_with_warnings", "success_with_warnings": return .yellow // Handle warnings if possible, otherwise map to existing
                                default: return .primary
                                }
                            }()
                            
                            Text(pipeline.status.capitalized)
                                .font(.caption)
                                .foregroundStyle(statusColor)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(pipeline.updatedAt) // Should format this date properly ideally, but string for now
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = URL(string: pipeline.webUrl) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .listStyle(.plain)
                .listRowInsets(EdgeInsets())
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .task {
            if pipelines.isEmpty {
                await loadPipelines()
            }
        }
    }
    
    private func loadPipelines() async {
        isLoadingPipelines = true
        pipelineError = nil
        let client = GitLabClient(authService: authService)
        
        do {
            // 1. Fetch running pipelines
            async let runningTask = client.fetchProjectPipelines(projectId: project.id, status: "running")
            
            // 2. Fetch failed pipelines
            async let failedTask = client.fetchProjectPipelines(projectId: project.id, status: "failed")
            
            let (runningPipelines, failedPipelines) = try await (runningTask, failedTask)
            
            // 3. Filter failed pipelines (last 24h)
            let callbackDate = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            // Fallback formatter without fractional seconds if needed
            let isoFormatterSimple = ISO8601DateFormatter()
            isoFormatterSimple.formatOptions = [.withInternetDateTime]
            
            let recentFailedPipelines = failedPipelines.filter { pipeline in
                if let date = isoFormatter.date(from: pipeline.updatedAt) ?? isoFormatterSimple.date(from: pipeline.updatedAt) {
                    return date > callbackDate
                }
                return false
            }
            
            // 4. Merge and Sort
            // Combine running + recent failed
            let combinedPipelines = (runningPipelines + recentFailedPipelines).sorted(by: { $0.id > $1.id })
            
            await MainActor.run {
                self.pipelines = combinedPipelines
            }
            
            if combinedPipelines.isEmpty {
                 // Check existence logic allows distinguishing distinct empty states
                let anyPipelines = try await client.fetchProjectPipelines(projectId: project.id, status: nil)
                
                await MainActor.run {
                    if anyPipelines.isEmpty {
                        self.pipelineEmptyMessage = "No pipelines found for this project"
                    } else {
                         self.pipelineEmptyMessage = "No active or recently failed pipelines"
                    }
                    self.isLoadingPipelines = false
                }
            } else {
                await MainActor.run {
                    self.isLoadingPipelines = false
                }
            }
            
        } catch {
            await MainActor.run {
                self.pipelineError = error.localizedDescription
                self.isLoadingPipelines = false
            }
        }
    }
}
