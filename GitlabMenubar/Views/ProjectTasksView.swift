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
    @State private var allTasks: [GitLabClient.Issue] = []  // All fetched tasks
    @State private var labelsWithCounts: [(label: GitLabClient.Label, count: Int)] = []  // Only labels with tasks
    @State private var isLoading = false
    @State private var taskError: String?
    
    init(project: GitLabClient.Project) {
        self.project = project
        // Per-project label persistence
        self._storedLabel = AppStorage(wrappedValue: "", "lastSelectedLabel_\(project.id)")
    }
    
    var filteredTasks: [GitLabClient.Issue] {
        if selectedLabel.isEmpty {
            return allTasks
        } else {
            return allTasks.filter { task in
                task.labels.contains(selectedLabel)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Label filter chips
            if !labelsWithCounts.isEmpty || isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "All" chip with total count
                        LabelChip(
                            name: "All",
                            count: allTasks.count,
                            color: nil,
                            isSelected: selectedLabel.isEmpty,
                            action: {
                                selectedLabel = ""
                                storedLabel = ""
                            }
                        )

                        // Label chips with counts (only labels that have tasks)
                        ForEach(labelsWithCounts, id: \.label.id) { item in
                            LabelChip(
                                name: item.label.name,
                                count: item.count,
                                color: item.label.color,
                                isSelected: selectedLabel == item.label.name,
                                action: {
                                    selectedLabel = item.label.name
                                    storedLabel = item.label.name
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
            if isLoading && allTasks.isEmpty {
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
                        Task { await loadTasksAndLabels() }
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if filteredTasks.isEmpty {
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
                List(filteredTasks) { task in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(task.title)
                                .font(.body)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text("#\(task.iid) · opened")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let assignee = task.assignees?.first {
                                    Text("·")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "person.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(assignee.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
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
            // Load tasks and extract labels on view appear
            if allTasks.isEmpty {
                await loadTasksAndLabels()
            }
        }
    }

    private func loadTasksAndLabels() async {
        isLoading = true
        taskError = nil
        let client = GitLabClient(authService: authService)

        do {
            // Fetch all tasks (no label filter)
            let fetchedTasks = try await client.fetchProjectIssues(projectId: project.id, labels: nil)

            // Fetch all project labels to get color info
            let allProjectLabels = try await client.fetchProjectLabels(projectId: project.id)

            // Extract labels that are actually used in tasks
            var labelCountMap: [String: Int] = [:]
            for task in fetchedTasks {
                for labelName in task.labels {
                    labelCountMap[labelName, default: 0] += 1
                }
            }

            // Create label objects with counts (only for labels with tasks)
            let labelsWithCounts = allProjectLabels
                .compactMap { projectLabel -> (label: GitLabClient.Label, count: Int)? in
                    guard let count = labelCountMap[projectLabel.name] else { return nil }
                    return (label: projectLabel, count: count)
                }
                .sorted { lhs, rhs in
                    // Sort by priority, then by count
                    let priorityOrder = ["todo", "in progress", "in review", "ready to test", "pending release"]

                    let lhsNormalized = lhs.label.name.lowercased()
                    let rhsNormalized = rhs.label.name.lowercased()

                    let lhsPriority = priorityOrder.firstIndex(where: { lhsNormalized.contains($0) })
                    let rhsPriority = priorityOrder.firstIndex(where: { rhsNormalized.contains($0) })

                    // Both have priority - sort by priority order
                    if let lp = lhsPriority, let rp = rhsPriority {
                        return lp < rp
                    }
                    // Only lhs has priority
                    if lhsPriority != nil {
                        return true
                    }
                    // Only rhs has priority
                    if rhsPriority != nil {
                        return false
                    }
                    // Neither has priority - sort by count (descending), then alphabetically
                    if lhs.count != rhs.count {
                        return lhs.count > rhs.count
                    }
                    return lhs.label.name < rhs.label.name
                }

            await MainActor.run {
                self.allTasks = fetchedTasks
                self.labelsWithCounts = labelsWithCounts
                self.isLoading = false

                // Determine initial filter
                determineInitialFilter()
            }
        } catch {
            await MainActor.run {
                self.taskError = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func determineInitialFilter() {
        // 1. Check if stored label exists in tasks
        if labelsWithCounts.contains(where: { $0.label.name == storedLabel }) {
            selectedLabel = storedLabel
            return
        }

        // 2. Check for "ToDo" (case-insensitive)
        if let todoLabel = labelsWithCounts.first(where: {
            $0.label.name.localizedCaseInsensitiveContains("todo") && $0.label.name.count <= 6
        }) {
            selectedLabel = todoLabel.label.name
            storedLabel = todoLabel.label.name
            return
        }

        // 3. Fallback to All
        selectedLabel = ""
        storedLabel = ""
    }
}

// MARK: - Label Chip Component
struct LabelChip: View {
    let name: String
    let count: Int
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

                // Count badge
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
