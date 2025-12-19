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
    
    var body: some View {
        Group {
            if isLoadingMRs && mrs.isEmpty {
                ProgressView()
            } else if let error = mrError {
                VStack {
                    Text("Error loading MRs")
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await loadMRs() }
                    }
                }
            } else if mrs.isEmpty {
                VStack(spacing: 8) {
                    Text("No relevant MRs found")
                        .foregroundStyle(.secondary)
                    Text("Showing MRs created by you or assigned to you as reviewer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            } else {
                List(mrs) { mr in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(mr.title)
                                .font(.body)
                                .lineLimit(1)
                            
                            HStack(spacing: 4) {
                                let statusText: String = {
                                    if mr.state == "opened" {
                                        if mr.detailedMergeStatus == "mergeable" {
                                            return "Pending Merge"
                                        } else if let reviewers = mr.reviewers, !reviewers.isEmpty {
                                            return "In Review"
                                        } else {
                                            return "Open"
                                        }
                                    } else {
                                        return mr.state
                                    }
                                }()
                                
                                let statusColor: Color = {
                                    switch statusText {
                                    case "Pending Merge": return .green
                                    case "In Review": return .orange
                                    default: return .secondary
                                    }
                                }()
                                
                                Text("#\(mr.iid) · \(statusText)")
                                    .foregroundStyle(statusColor)
                            }
                            .font(.caption)
                            
                            if let assignees = mr.assignees, !assignees.isEmpty {
                                Text("Assignee: \(assignees.map(\.name).joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let reviewers = mr.reviewers, !reviewers.isEmpty {
                                Text("Reviewers: \(reviewers.map(\.name).joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = URL(string: mr.webUrl) {
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
            // 1. Ensure we have the current user
            if authService.currentUser == nil {
                let user = try await client.fetchCurrentUser()
                await MainActor.run {
                    authService.currentUser = user
                }
            }
            
            guard let currentUser = authService.currentUser else {
                throw GitLabClient.ClientError.unauthorized(nil)
            }
            
            // 2. Fetch "Created by me"
            async let createdByMe = client.fetchProjectMergeRequests(projectId: project.id, scope: "created_by_me")
            
            // 3. Fetch "Reviewer"
            async let reviewing = client.fetchProjectMergeRequests(projectId: project.id, reviewerId: currentUser.id)
            
            let (myMRs, reviewingMRs) = try await (createdByMe, reviewing)
            
            // 4. Merge and Deduplicate
            var allMRs = myMRs
            let existingIds = Set(myMRs.map { $0.id })
            for mr in reviewingMRs {
                if !existingIds.contains(mr.id) {
                    allMRs.append(mr)
                }
            }
            
            // Sort by ID descending (newest first)
            allMRs.sort(by: { $0.id > $1.id })
            
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
