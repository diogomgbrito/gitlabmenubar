//
//  ProjectTasksView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 17/12/2025.
//

import SwiftUI

struct ProjectTasksView: View {
    let project: GitLabClient.Project
    let filterLabel: String
    @EnvironmentObject var authService: AuthenticationService
    
    @State private var tasks: [GitLabClient.Issue] = []
    @State private var isLoadingTasks = false
    @State private var taskError: String?
    
    var body: some View {
        Group {
            if isLoadingTasks && tasks.isEmpty {
                ProgressView()
            } else if let error = taskError {
                VStack {
                    Text("Error loading tasks")
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await loadTasks() }
                    }
                }
            } else if tasks.isEmpty {
                VStack(spacing: 8) {
                    Text("No open tasks found")
                        .foregroundStyle(.secondary)
                    if !filterLabel.isEmpty {
                        Text("Filter: \(filterLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                List(tasks) { task in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(task.title)
                                .font(.body)
                                .lineLimit(1)
                            Text("#\(task.iid) · opened")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = URL(string: task.webUrl) {
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
        .task(id: filterLabel) {
            await loadTasks()
        }
    }
    
    private func loadTasks() async {
        isLoadingTasks = true
        taskError = nil
        let client = GitLabClient(authService: authService)
        
        do {
            let filterLabels = filterLabel.isEmpty ? nil : [filterLabel]
            let fetchedTasks = try await client.fetchProjectIssues(projectId: project.id, labels: filterLabels)
            await MainActor.run {
                self.tasks = fetchedTasks
                self.isLoadingTasks = false
            }
        } catch {
            await MainActor.run {
                self.taskError = error.localizedDescription
                self.isLoadingTasks = false // Ensure loading state is cleared
            }
        }
    }
}
