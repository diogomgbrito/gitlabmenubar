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
    
    @AppStorage("lastSelectedLabel") private var storedLabel: String = ""
    @State private var currentLabel: String = ""
    @State private var labels: [GitLabClient.Label] = []
    
    // Default to tasks tab
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(project.name)
                    .font(.headline)
                
                Spacer()
                
                Menu {
                    Button(action: {
                        updateFilter(to: "")
                    }) {
                        if currentLabel.isEmpty {
                            Label("All Issues", systemImage: "checkmark")
                        } else {
                            Text("All Issues")
                        }
                    }
                    
                    Divider()
                    
                    ForEach(labels) { label in
                        Button(action: {
                            updateFilter(to: label.name)
                        }) {
                            if currentLabel == label.name {
                                Label(label.name, systemImage: "checkmark")
                            } else {
                                Text(label.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(currentLabel.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            .padding(.top, 20)
            .padding(.horizontal)
            .padding(.bottom, 10)
            .background(.regularMaterial)
            
            Divider()
            
            TabView(selection: $selectedTab) {
                ProjectTasksView(project: project, filterLabel: currentLabel)
                    .tabItem {
                        Label("Tasks", systemImage: "checklist")
                    }
                    .tag(0)
                
                ProjectMRsView(project: project)
                    .tabItem {
                        Label("MRs", systemImage: "arrow.triangle.pull")
                    }
                    .tag(1)
                
                ProjectPipelinesView(project: project)
                    .tabItem {
                        Label("Pipelines", systemImage: "hammer")
                    }
                    .tag(2)
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
             if labels.isEmpty {
                 await loadLabels()
             }
        }
    }
    
    private func updateFilter(to labelName: String) {
        currentLabel = labelName
        storedLabel = labelName
        // No manual reload needed, ProjectTasksView observes filterLabel
    }
    
    private func loadLabels() async {
        let client = GitLabClient(authService: authService)
        do {
            let fetchedLabels = try await client.fetchProjectLabels(projectId: project.id)
            
            await MainActor.run {
                self.labels = fetchedLabels.sorted(by: { $0.name < $1.name })
                determineInitialFilter()
            }
            
        } catch {
            print("Error loading labels: \(error)")
        }
    }
    
    private func determineInitialFilter() {
        // 1. Check if stored label exists in this project
        if let match = labels.first(where: { $0.name == storedLabel }) {
            currentLabel = match.name
            return
        }
        
        // 2. Check for "ToDo" (case-insensitive)
        if let todoMatch = labels.first(where: { $0.name.localizedCaseInsensitiveContains("todo") && $0.name.count <= 6 }) { // Basic heuristic for "todo", "ToDo", "TODO"
            currentLabel = todoMatch.name
            return
        }
        
        // 3. Fallback to All
        currentLabel = ""
    }
}

#Preview {
    ProjectDetailView(project: GitLabClient.Project(id: 1, name: "Test Project", pathWithNamespace: "group/test-project", starCount: 10, webUrl: "https://gitlab.com/group/test-project"))
        .environmentObject(AuthenticationService())
}
