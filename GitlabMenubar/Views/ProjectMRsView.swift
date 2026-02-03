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
            VStack(spacing: 8) {
                HStack {
                    Picker("State", selection: $selectedState) {
                        ForEach(MRState.allCases, id: \.self) { state in
                            Text(state.displayName).tag(state)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedState) { _ in
                        Task { await loadMRs() }
                    }
                    
                    Toggle("My MRs", isOn: $showMyMRsOnly)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                        .onChange(of: showMyMRsOnly) { _ in
                            Task { await loadMRs() }
                        }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Button(action: {
                    if let url = URL(string: "\(project.webUrl)/-/merge_requests") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("View all MRs")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 4)
                
                Divider()
            }
            .background(Color(NSColor.windowBackgroundColor))
            .zIndex(1)
            
            ScrollView {
                Group {
                    if isLoadingMRs && mrs.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .padding()
                    } else if mrs.isEmpty {
                        VStack(spacing: 8) {
                            Text("No MRs found")
                                .foregroundStyle(.secondary)
                            if showMyMRsOnly {
                                Text("Showing MRs created by you or assigned to you as reviewer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(mrs) { mr in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(mr.title)
                                        .font(.body)
                                        .lineLimit(1)

                                    HStack(spacing: 8) {
                                        // Assignees on the left
                                        if let assignees = mr.assignees, !assignees.isEmpty {
                                            HStack(spacing: 4) {
                                                Image(systemName: "person.fill")
                                                Text(assignees.map(\.name).joined(separator: ", "))
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        // MR # and state in the middle
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
                                                } else if mr.state == "merged" {
                                                    return "Merged"
                                                } else {
                                                    return mr.state
                                                }
                                            }()

                                            let statusColor: Color = {
                                                switch statusText {
                                                case "Pending Merge": return .green
                                                case "In Review": return .orange
                                                case "Merged": return .purple
                                                default: return .secondary
                                                }
                                            }()

                                            Text("#\(mr.iid) · \(statusText)")
                                                .foregroundStyle(statusColor)
                                        }
                                        .font(.caption)

                                        Spacer()

                                        // Reviewers on the right
                                        if let reviewers = mr.reviewers, !reviewers.isEmpty {
                                            HStack(spacing: 4) {
                                                Image(systemName: "eye.fill")
                                                Text(reviewers.map(\.name).joined(separator: ", "))
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let url = URL(string: mr.webUrl) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                
                                if mr.id != mrs.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
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
                    await MainActor.run {
                        authService.currentUser = user
                    }
                }
                
                guard let currentUser = authService.currentUser else {
                    throw GitLabClient.ClientError.unauthorized(nil)
                }
                
                async let createdByMe = client.fetchProjectMergeRequests(projectId: project.id, scope: "created_by_me", state: selectedState.rawValue)
                async let reviewing = client.fetchProjectMergeRequests(projectId: project.id, reviewerId: currentUser.id, state: selectedState.rawValue)
                
                let (myMRs, reviewingMRs) = try await (createdByMe, reviewing)
                
                allMRs = myMRs
                let existingIds = Set(myMRs.map { $0.id })
                for mr in reviewingMRs {
                    if !existingIds.contains(mr.id) {
                        allMRs.append(mr)
                    }
                }
            } else {
                allMRs = try await client.fetchProjectMergeRequests(projectId: project.id, state: selectedState.rawValue)
            }
            
            if selectedState == .merged {
                allMRs.sort { mr1, mr2 in
                    guard let date1 = mr1.mergedAt, let date2 = mr2.mergedAt else {
                        return mr1.id > mr2.id
                    }
                    return date1 > date2
                }
                allMRs = Array(allMRs.prefix(10))
            } else {
                allMRs.sort(by: { $0.id > $1.id })
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
