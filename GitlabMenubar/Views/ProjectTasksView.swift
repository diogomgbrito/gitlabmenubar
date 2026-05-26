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
    @State private var allTasks: [GitLabClient.Issue] = []
    @State private var labelsWithCounts: [(label: GitLabClient.Label, count: Int)] = []
    @State private var isLoading = false
    @State private var taskError: String?

    init(project: GitLabClient.Project) {
        self.project = project
        self._storedLabel = AppStorage(wrappedValue: "", "lastSelectedLabel_\(project.id)")
    }

    var filteredTasks: [GitLabClient.Issue] {
        if selectedLabel.isEmpty {
            return allTasks
        } else {
            return allTasks.filter { $0.labels.contains(selectedLabel) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Label filter chips
            if !labelsWithCounts.isEmpty || isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        LabelChip(name: "All", count: allTasks.count, color: nil, isSelected: selectedLabel.isEmpty) {
                            selectedLabel = ""
                            storedLabel = ""
                        }
                        ForEach(labelsWithCounts, id: \.label.id) { item in
                            LabelChip(name: item.label.name, count: item.count, color: item.label.color, isSelected: selectedLabel == item.label.name) {
                                selectedLabel = item.label.name
                                storedLabel = item.label.name
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                Divider()
            }

            // Task list
            if isLoading && allTasks.isEmpty {
                VStack {
                    ProgressView().padding(.top, 24)
                    Spacer()
                }
            } else if let error = taskError {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error loading tasks")
                        .font(.system(size: 13, weight: .medium))
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await loadTasksAndLabels() }
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if filteredTasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No open tasks found")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if !selectedLabel.isEmpty {
                        Text("Filter: \(selectedLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(filteredTasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 13))
                            .lineLimit(2)

                        HStack(spacing: 4) {
                            Text("#\(task.iid)")
                                .foregroundStyle(.secondary)
                            if let assignee = task.assignees?.first {
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "person.fill")
                                Text(assignee.name)
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = URL(string: task.webUrl) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task {
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
            let fetchedTasks = try await client.fetchProjectIssues(projectId: project.id, labels: nil)
            let allProjectLabels = try await client.fetchProjectLabels(projectId: project.id)

            var labelCountMap: [String: Int] = [:]
            for task in fetchedTasks {
                for labelName in task.labels {
                    labelCountMap[labelName, default: 0] += 1
                }
            }

            let labelsWithCounts = allProjectLabels
                .compactMap { projectLabel -> (label: GitLabClient.Label, count: Int)? in
                    guard let count = labelCountMap[projectLabel.name] else { return nil }
                    return (label: projectLabel, count: count)
                }
                .sorted { lhs, rhs in
                    let priorityOrder = ["todo", "in progress", "in review", "ready to test", "pending release"]
                    let lhsNormalized = lhs.label.name.lowercased()
                    let rhsNormalized = rhs.label.name.lowercased()
                    let lhsPriority = priorityOrder.firstIndex(where: { lhsNormalized.contains($0) })
                    let rhsPriority = priorityOrder.firstIndex(where: { rhsNormalized.contains($0) })
                    if let lp = lhsPriority, let rp = rhsPriority { return lp < rp }
                    if lhsPriority != nil { return true }
                    if rhsPriority != nil { return false }
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                    return lhs.label.name < rhs.label.name
                }

            await MainActor.run {
                self.allTasks = fetchedTasks
                self.labelsWithCounts = labelsWithCounts
                self.isLoading = false
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
        if labelsWithCounts.contains(where: { $0.label.name == storedLabel }) {
            selectedLabel = storedLabel
            return
        }
        if let todoLabel = labelsWithCounts.first(where: {
            $0.label.name.localizedCaseInsensitiveContains("todo") && $0.label.name.count <= 6
        }) {
            selectedLabel = todoLabel.label.name
            storedLabel = todoLabel.label.name
            return
        }
        selectedLabel = ""
        storedLabel = ""
    }
}

// MARK: - Label Chip

struct LabelChip: View {
    let name: String
    let count: Int
    let color: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let colorHex = color {
                    Circle()
                        .fill(Color(hex: colorHex) ?? .gray)
                        .frame(width: 6, height: 6)
                }
                Text(name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
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
