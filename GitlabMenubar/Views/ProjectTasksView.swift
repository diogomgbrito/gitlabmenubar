//
//  ProjectTasksView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 17/12/2025.
//

import SwiftUI

struct ProjectTasksView: View {
    let project: GitLabClient.Project
    @EnvironmentObject var authService: AuthenticationService
    
    @AppStorage private var storedLabel: String
    @State private var selectedLabel: String = ""
    @State private var labels: [GitLabClient.Label] = []
    @State private var isLoadingLabels = false
    @State private var labelsReady = false  // Track when labels are loaded and filter is set
    
    @State private var tasks: [GitLabClient.Issue] = []
    @State private var isLoadingTasks = false
    @State private var taskError: String?
    
    init(project: GitLabClient.Project) {
        self.project = project
        // Per-project label persistence
        self._storedLabel = AppStorage(wrappedValue: "", "lastSelectedLabel_\(project.id)")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Label filter chips
            if !labels.isEmpty || isLoadingLabels {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "All" chip
                        LabelChip(
                            name: "All",
                            color: nil,
                            isSelected: selectedLabel.isEmpty,
                            action: {
                                selectedLabel = ""
                                storedLabel = ""
                            }
                        )
                        
                        // Label chips
                        ForEach(labels) { label in
                            LabelChip(
                                name: label.name,
                                color: label.color,
                                isSelected: selectedLabel == label.name,
                                action: {
                                    selectedLabel = label.name
                                    storedLabel = label.name
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                Divider()
            }
            
            // Task list
            if isLoadingTasks && tasks.isEmpty {
                VStack {
                    ProgressView()
                        .padding(.top, 20)
                    Spacer()
                }
            } else if let error = taskError {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error loading tasks")
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await loadTasks() }
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No open tasks found")
                        .foregroundStyle(.secondary)
                    if !selectedLabel.isEmpty {
                        Text("Filter: \(selectedLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .task {
            // Load labels first, then tasks will load automatically when selectedLabel is set
            if labels.isEmpty {
                await loadLabels()
            }
        }
        .onChange(of: labelsReady) { _, isReady in
            // Load tasks once labels are ready and initial filter is determined
            if isReady {
                Task {
                    await loadTasks()
                }
            }
        }
        .onChange(of: selectedLabel) { _, _ in
            // Reload tasks whenever the selected label changes
            if labelsReady {  // Only reload if labels are already ready
                Task {
                    await loadTasks()
                }
            }
        }
    }
    
    private func loadLabels() async {
        isLoadingLabels = true
        let client = GitLabClient(authService: authService)
        
        do {
            let fetchedLabels = try await client.fetchProjectLabels(projectId: project.id)
            
            await MainActor.run {
                self.labels = sortLabels(fetchedLabels)
                self.isLoadingLabels = false
                determineInitialFilter()
                self.labelsReady = true  // Signal that labels and filter are ready
            }
        } catch {
            await MainActor.run {
                print("Error loading labels: \(error)")
                self.isLoadingLabels = false
                self.labelsReady = true  // Still set ready even on error, use empty filter
            }
        }
    }
    
    private func sortLabels(_ labels: [GitLabClient.Label]) -> [GitLabClient.Label] {
        // Define priority order (case-insensitive matching)
        let priorityOrder = [
            "todo",
            "in progress",
            "in review",
            "ready to test",
            "pending release"
        ]
        
        var priorityLabels: [GitLabClient.Label] = []
        var otherLabels: [GitLabClient.Label] = []
        
        for label in labels {
            let normalizedName = label.name.lowercased()
            if let index = priorityOrder.firstIndex(where: { normalizedName.contains($0) }) {
                // Insert at the correct priority position
                if priorityLabels.isEmpty {
                    priorityLabels.append(label)
                } else {
                    // Find the correct position based on priority order
                    var inserted = false
                    for (i, existingLabel) in priorityLabels.enumerated() {
                        let existingNormalized = existingLabel.name.lowercased()
                        if let existingIndex = priorityOrder.firstIndex(where: { existingNormalized.contains($0) }),
                           index < existingIndex {
                            priorityLabels.insert(label, at: i)
                            inserted = true
                            break
                        }
                    }
                    if !inserted {
                        priorityLabels.append(label)
                    }
                }
            } else {
                otherLabels.append(label)
            }
        }
        
        // Sort other labels alphabetically
        otherLabels.sort { $0.name < $1.name }
        
        // Combine: priority labels first, then alphabetically sorted others
        return priorityLabels + otherLabels
    }
    
    private func determineInitialFilter() {
        // 1. Check if stored label exists in this project
        if let match = labels.first(where: { $0.name == storedLabel }) {
            selectedLabel = match.name
            return
        }
        
        // 2. Check for "ToDo" (case-insensitive)
        if let todoMatch = labels.first(where: { $0.name.localizedCaseInsensitiveContains("todo") && $0.name.count <= 6 }) {
            selectedLabel = todoMatch.name
            storedLabel = todoMatch.name
            return
        }
        
        // 3. Fallback to All
        selectedLabel = ""
        storedLabel = ""
    }
    
    private func loadTasks() async {
        isLoadingTasks = true
        taskError = nil
        let client = GitLabClient(authService: authService)
        
        do {
            let filterLabels = selectedLabel.isEmpty ? nil : [selectedLabel]
            let fetchedTasks = try await client.fetchProjectIssues(projectId: project.id, labels: filterLabels)
            await MainActor.run {
                self.tasks = fetchedTasks
                self.isLoadingTasks = false
            }
        } catch {
            await MainActor.run {
                self.taskError = error.localizedDescription
                self.isLoadingTasks = false
            }
        }
    }
}

// MARK: - Label Chip Component
struct LabelChip: View {
    let name: String
    let color: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // Color indicator dot
                if let colorHex = color {
                    Circle()
                        .fill(Color(hex: colorHex) ?? .gray)
                        .frame(width: 8, height: 8)
                }
                
                Text(name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : Color(NSColor.controlBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}
