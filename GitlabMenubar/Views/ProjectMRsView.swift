//
//  ProjectMRsView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 17/12/2025.
//

import SwiftUI

struct ProjectMRsView: View {
    let project: GitLabClient.Project
    @EnvironmentObject var authService: AuthenticationService

    @State private var mrs: [GitLabClient.MergeRequest] = []
    @State private var isLoadingMRs = false
    @State private var mrError: String?
    @State private var showMyMRsOnly = true
    @State private var selectedState: MRState = .open

    enum MRState: String, CaseIterable {
        case open = "opened"
        case merged = "merged"

        var displayName: String {
            switch self {
            case .open: return "Open"
            case .merged: return "Merged"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter header
            HStack(spacing: 16) {
                // State tabs
                ForEach(MRState.allCases, id: \.self) { state in
                    Button(state.displayName) {
                        selectedState = state
                        Task { await loadMRs() }
                    }
                    .font(.system(size: 12, weight: selectedState == state ? .semibold : .regular))
                    .foregroundStyle(selectedState == state ? .primary : .secondary)
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if selectedState == state {
                            Rectangle()
                                .frame(height: 1.5)
                                .foregroundStyle(Color.accentColor)
                                .offset(y: 6)
                        }
                    }
                }

                Spacer()

                // My MRs toggle
                Button {
                    showMyMRsOnly.toggle()
                    Task { await loadMRs() }
                } label: {
                    Image(systemName: showMyMRsOnly ? "person.fill" : "person")
                        .font(.system(size: 13))
                        .foregroundStyle(showMyMRsOnly ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(showMyMRsOnly ? "Showing my MRs" : "Showing all MRs")

                // External link
                Button {
                    if let url = URL(string: "\(project.webUrl)/-/merge_requests") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Content
            if isLoadingMRs && mrs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = mrError {
                VStack(spacing: 8) {
                    Text("Error loading MRs")
                        .font(.system(size: 13, weight: .medium))
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await loadMRs() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if mrs.isEmpty {
                VStack(spacing: 6) {
                    Text("No MRs found")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if showMyMRsOnly {
                        Text("Showing MRs created by you or assigned for review")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(mrs) { mr in
                    let statusText: String = {
                        if mr.state == "opened" {
                            if mr.detailedMergeStatus == "mergeable" { return "Pending Merge" }
                            if let reviewers = mr.reviewers, !reviewers.isEmpty { return "In Review" }
                            return "Open"
                        } else if mr.state == "merged" {
                            return "Merged"
                        }
                        return mr.state
                    }()

                    let statusColor: Color = {
                        switch statusText {
                        case "Pending Merge": return .green
                        case "In Review": return .orange
                        case "Merged": return .purple
                        default: return .secondary
                        }
                    }()

                    NavigationLink {
                        MRDetailView(project: project, mr: mr)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mr.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)

                            HStack(spacing: 5) {
                                IIDChip(kind: .mergeRequest, iid: mr.iid)
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 5, height: 5)
                                Text(statusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let assignees = mr.assignees, !assignees.isEmpty {
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "person.fill")
                                    Text(assignees.map(\.name).joined(separator: ", "))
                                        .lineLimit(1)
                                } else if let reviewers = mr.reviewers, !reviewers.isEmpty {
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "eye.fill")
                                    Text(reviewers.map(\.name).joined(separator: ", "))
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task {
            if mrs.isEmpty {
                await loadMRs()
            }
        }
    }

    private func loadMRs() async {
        isLoadingMRs = true
        mrError = nil
        let client = GitLabClient(authService: authService)

        do {
            var allMRs: [GitLabClient.MergeRequest]

            if showMyMRsOnly {
                if authService.currentUser == nil {
                    let user = try await client.fetchCurrentUser()
                    await MainActor.run { authService.currentUser = user }
                }

                guard let currentUser = authService.currentUser else {
                    throw GitLabClient.ClientError.unauthorized(nil)
                }

                async let createdByMe = client.fetchProjectMergeRequests(projectId: project.id, scope: "created_by_me", state: selectedState.rawValue)
                async let reviewing = client.fetchProjectMergeRequests(projectId: project.id, reviewerId: currentUser.id, state: selectedState.rawValue)

                let (myMRs, reviewingMRs) = try await (createdByMe, reviewing)

                allMRs = myMRs
                let existingIds = Set(myMRs.map { $0.id })
                for mr in reviewingMRs where !existingIds.contains(mr.id) {
                    allMRs.append(mr)
                }
            } else {
                allMRs = try await client.fetchProjectMergeRequests(projectId: project.id, state: selectedState.rawValue)
            }

            if selectedState == .merged {
                allMRs.sort {
                    guard let d1 = $0.mergedAt, let d2 = $1.mergedAt else { return $0.id > $1.id }
                    return d1 > d2
                }
                allMRs = Array(allMRs.prefix(10))
            } else {
                allMRs.sort { $0.id > $1.id }
            }

            await MainActor.run {
                self.mrs = allMRs
                self.isLoadingMRs = false
            }
        } catch {
            await MainActor.run {
                self.mrError = error.localizedDescription
                self.isLoadingMRs = false
            }
        }
    }
}
