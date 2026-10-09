//
//  ReviewsView.swift
//  GitlabMenubar
//

import SwiftUI

struct ReviewsView: View {
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    struct ReviewItem: Identifiable {
        let mr: GitLabClient.MergeRequest
        let project: GitLabClient.Project
        let reason: String?

        var id: Int { mr.id }
    }

    @State private var awaitingReview: [ReviewItem] = []
    @State private var changedSinceReview: [ReviewItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var totalCount: Int { awaitingReview.count + changedSinceReview.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text("Reviews")
                    .font(.system(size: 15, weight: .semibold))

                if totalCount > 0 {
                    Text("\(totalCount)")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if isLoading && totalCount == 0 {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text("Error loading reviews")
                        .font(.system(size: 13, weight: .medium))
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await load() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if totalCount == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text(SettingsManager.shared.watchedProjectIds.isEmpty ? "No watched projects" : "No MRs need your attention")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    if SettingsManager.shared.watchedProjectIds.isEmpty {
                        Text("Tap the bell on a project to include it here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !awaitingReview.isEmpty {
                        Section {
                            ForEach(awaitingReview) { item in
                                row(item)
                            }
                        } header: {
                            sectionHeader("Awaiting your review")
                        }
                    }
                    if !changedSinceReview.isEmpty {
                        Section {
                            ForEach(changedSinceReview) { item in
                                row(item)
                            }
                        } header: {
                            sectionHeader("Changed since your review")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            if totalCount == 0 {
                await load()
            }
        }
        .refreshesReviewSessions()
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    @ViewBuilder
    private func row(_ item: ReviewItem) -> some View {
        let target = ReviewTarget(project: item.project, mr: item.mr)
        HStack(alignment: .center, spacing: 8) {
            NavigationLink {
                MRDetailView(project: item.project, mr: item.mr)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.mr.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        Text("!\(item.mr.iid)")
                            .foregroundStyle(Color.accentColor)
                        Text("·")
                        Text(item.project.name)
                            .lineLimit(1)
                        Text("·")
                        Text(item.mr.author.username)
                            .lineLimit(1)
                        if let reason = item.reason {
                            Text("·")
                            Text(reason)
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ReviewSessionBadge(target: target)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ReviewControls(target: target, style: .compact)
        }
        .listRowBackground(Color.clear)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        let client = GitLabClient(authService: authService)

        do {
            let me = try await client.fetchCurrentUser()
            let watchedIds = SettingsManager.shared.watchedProjectIds
            let projects = try await client.fetchStarredProjects().filter { watchedIds.contains($0.id) }

            var awaiting: [ReviewItem] = []
            var changed: [ReviewItem] = []

            // Cap concurrency: self-hosted GitLab instances choke on a burst of
            // one connection per project (plus per-MR notes calls).
            let maxConcurrent = 3
            try await withThrowingTaskGroup(of: [(GitLabClient.MergeRequest, GitLabClient.Project, [GitLabClient.Note])].self) { group in
                var iterator = projects.makeIterator()
                var inFlight = 0

                func addNextTask() {
                    guard let project = iterator.next() else { return }
                    inFlight += 1
                    group.addTask {
                        guard let mrs = try? await client.fetchProjectMergeRequests(projectId: project.id, reviewerId: me.id, state: "opened"), !mrs.isEmpty else {
                            return []
                        }
                        var results: [(GitLabClient.MergeRequest, GitLabClient.Project, [GitLabClient.Note])] = []
                        for mr in mrs {
                            let notes = (try? await client.fetchMRNotes(projectId: project.id, mrIid: mr.iid)) ?? []
                            results.append((mr, project, notes))
                        }
                        return results
                    }
                }

                for _ in 0..<maxConcurrent { addNextTask() }

                while inFlight > 0 {
                    guard let batch = try await group.next() else { break }
                    inFlight -= 1
                    addNextTask()

                    for (mr, project, notes) in batch {
                        let classification = classify(mr: mr, notes: notes, myId: me.id)
                        switch classification {
                        case .awaiting:
                            awaiting.append(ReviewItem(mr: mr, project: project, reason: nil))
                        case .changed(let reason):
                            changed.append(ReviewItem(mr: mr, project: project, reason: reason))
                        case .none:
                            break
                        }
                    }
                }
            }

            awaiting.sort { ($0.mr.updatedAt ?? "") > ($1.mr.updatedAt ?? "") }
            changed.sort { ($0.mr.updatedAt ?? "") > ($1.mr.updatedAt ?? "") }

            await MainActor.run {
                self.awaitingReview = awaiting
                self.changedSinceReview = changed
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private enum Classification {
        case awaiting
        case changed(String)
        case none
    }

    /// - No non-system notes from me → awaiting my first review.
    /// - I have notes, and someone else was active after my last one → needs re-review.
    /// - I have notes and nothing happened since → drop from the list.
    private func classify(mr: GitLabClient.MergeRequest, notes: [GitLabClient.Note], myId: Int) -> Classification {
        let myNotes = notes.filter { $0.author.id == myId && !$0.system }
        guard let lastMine = myNotes.map(\.createdAt).max() else {
            return .awaiting
        }

        let laterOthers = notes.filter { $0.author.id != myId && $0.createdAt > lastMine }
        guard !laterOthers.isEmpty else {
            return .none
        }

        let commitNotes = laterOthers.filter { $0.system && $0.body.contains("commit") }
        if !commitNotes.isEmpty {
            // System note body: "added 3 commits\n..." — extract the count when present
            if let first = commitNotes.first(where: { $0.body.hasPrefix("added") }),
               let countWord = first.body.split(separator: " ").dropFirst().first,
               let count = Int(countWord) {
                return .changed("\(count) new commit\(count == 1 ? "" : "s")")
            }
            return .changed("new commits")
        }
        return .changed("new replies")
    }
}

#Preview {
    NavigationStack {
        ReviewsView()
            .environmentObject(AuthenticationService())
    }
}
