//
//  MRDetailView.swift
//  GitlabMenubar
//

import SwiftUI

struct MRDetailView: View {
    let project: GitLabClient.Project
    let mr: GitLabClient.MergeRequest
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var detail: GitLabClient.MergeRequestDetail?
    @State private var closesIssues: [GitLabClient.Issue] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var reReviewStatus: [Int: ReReviewStatus] = [:]

    private enum ReReviewStatus: Equatable {
        case sending, sent, failed(String)
    }

    private var reviewers: [GitLabClient.User] { detail?.reviewers ?? mr.reviewers ?? [] }

    /// The people doing the work (author / assignees) can ping reviewers for another round.
    private var canReRequestReview: Bool {
        guard mr.state == "opened", let me = authService.currentUser else { return false }
        return mr.author.id == me.id || (mr.assignees ?? []).contains { $0.id == me.id }
    }

    private var statusText: String {
        if mr.state == "opened" {
            if mr.detailedMergeStatus == "mergeable" { return "Pending Merge" }
            if let reviewers = mr.reviewers, !reviewers.isEmpty { return "In Review" }
            return "Open"
        }
        return mr.state == "merged" ? "Merged" : mr.state
    }

    private var statusColor: Color {
        switch statusText {
        case "Pending Merge": return .green
        case "In Review": return .orange
        case "Merged": return .purple
        default: return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text(mr.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Meta row
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(statusColor)
                        IIDChip(kind: .mergeRequest, iid: mr.iid)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    // People & changes
                    VStack(alignment: .leading, spacing: 8) {
                        if let assignees = mr.assignees, !assignees.isEmpty {
                            metaRow(icon: "person.fill", text: assignees.map(\.name).joined(separator: ", "))
                        }
                        if !reviewers.isEmpty && !canReRequestReview {
                            metaRow(icon: "eye.fill", text: reviewers.map(\.name).joined(separator: ", "))
                        }
                        if let count = detail?.changesCount, !count.isEmpty {
                            metaRow(icon: "arrow.left.arrow.right", text: "\(count) file\(count == "1" ? "" : "s") changed")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // Reviewers, with re-request buttons for the author / assignees
                    if !reviewers.isEmpty && canReRequestReview {
                        Divider().padding(.top, 14)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reviewers")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(reviewers) { reviewer in
                                reviewerRow(reviewer)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    // Description
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                    } else if let error = loadError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    } else if let rawDesc = detail?.description, !rawDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let parsed = parseDescription(rawDesc)

                        Divider().padding(.top, 14)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            if parsed.hasImages {
                                Label("Contains images (not shown)", systemImage: "photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if parsed.hasVideos {
                                Label("Contains videos (not shown)", systemImage: "video")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let attr = try? AttributedString(markdown: parsed.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                                Text(attr)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                            } else {
                                Text(parsed.text)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    // Linked issues
                    if !closesIssues.isEmpty {
                        Divider().padding(.top, 14)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Closes")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(closesIssues) { issue in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        IIDChip(kind: .issue, iid: issue.iid)
                                        Text(issue.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(2)
                                    }
                                    if let desc = issue.description,
                                       !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        let parsed = parseDescription(desc)
                                        Text(parsed.text)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let url = URL(string: issue.webUrl) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    Spacer(minLength: 20)
                }
            }

            if mr.state == "opened" {
                Divider()
                ReviewControls(target: ReviewTarget(project: project, mr: mr))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            // Open in Browser button
            Divider()
            Button {
                if let url = URL(string: mr.webUrl) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Open in Browser")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .navigationBarBackButtonHidden(true)
        .task { await loadDetail() }
        .refreshesReviewSessions()
    }

    @ViewBuilder
    private func metaRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reviewerRow(_ reviewer: GitLabClient.User) -> some View {
        let status = reReviewStatus[reviewer.id]
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(reviewer.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if case .failed(let message) = status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text("@\(reviewer.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            switch status {
            case .sending:
                ProgressView().controlSize(.small)
            case .sent:
                Label("Requested", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            case .failed, nil:
                Button {
                    Task { await requestReReview(reviewer) }
                } label: {
                    Label(status == nil ? "Ask to review" : "Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Ask \(reviewer.name) for a new review (notifies them and adds a to-do)")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func requestReReview(_ reviewer: GitLabClient.User) async {
        reReviewStatus[reviewer.id] = .sending
        let client = GitLabClient(authService: authService)
        do {
            try await client.requestReReview(projectPath: project.pathWithNamespace, mrIid: mr.iid, userId: reviewer.id)
            reReviewStatus[reviewer.id] = .sent
        } catch {
            reReviewStatus[reviewer.id] = .failed(error.localizedDescription)
        }
    }

    private func loadDetail() async {
        isLoading = true
        loadError = nil
        let client = GitLabClient(authService: authService)
        if authService.currentUser == nil, let user = try? await client.fetchCurrentUser() {
            authService.currentUser = user
        }
        do {
            async let detailTask = client.fetchMergeRequestDetail(projectId: project.id, mrIid: mr.iid)
            async let closesTask = client.fetchMRClosesIssues(projectId: project.id, mrIid: mr.iid)
            let (fetchedDetail, closesIssues) = try await (detailTask, closesTask)

            // Parse #N refs from title and description, fetch each one
            var refsToFetch = parseIssueRefs(from: mr.title)
            if let desc = fetchedDetail.description {
                refsToFetch += parseIssueRefs(from: desc)
            }
            // Remove any already covered by closes_issues
            let coveredIids = Set(closesIssues.map(\.iid))
            let uniqueRefs = Set(refsToFetch).filter { !coveredIids.contains($0) }

            var refIssues: [GitLabClient.Issue] = []
            for iid in uniqueRefs {
                if let issue = try? await client.fetchProjectIssue(projectId: project.id, issueIid: iid) {
                    refIssues.append(issue)
                }
            }

            let allIssues = (closesIssues + refIssues).sorted { $0.iid < $1.iid }

            await MainActor.run {
                self.detail = fetchedDetail
                self.closesIssues = allIssues
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = "Could not load details"
                self.isLoading = false
            }
        }
    }

    private func parseIssueRefs(from text: String) -> [Int] {
        guard let re = try? NSRegularExpression(pattern: #"#(\d+)"#) else { return [] }
        let matches = re.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[range])
        }
    }

    private struct ParsedDescription {
        let text: String
        let hasImages: Bool
        let hasVideos: Bool
    }

    private func parseDescription(_ raw: String) -> ParsedDescription {
        var text = raw
        var hasImages = false
        var hasVideos = false

        // Markdown images: ![alt](url)
        if let re = try? NSRegularExpression(pattern: #"!\[.*?\]\(.*?\)"#) {
            let range = NSRange(text.startIndex..., in: text)
            if re.firstMatch(in: text, range: range) != nil { hasImages = true }
            text = re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // HTML img tags
        if let re = try? NSRegularExpression(pattern: #"<img[^>]*>"#, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            if re.firstMatch(in: text, range: range) != nil { hasImages = true }
            text = re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // HTML video tags
        if let re = try? NSRegularExpression(pattern: #"<video[\s\S]*?</video>"#, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            if re.firstMatch(in: text, range: range) != nil { hasVideos = true }
            text = re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // Collapse excess blank lines
        if let re = try? NSRegularExpression(pattern: #"\n{3,}"#) {
            text = re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n")
        }

        return ParsedDescription(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            hasImages: hasImages,
            hasVideos: hasVideos
        )
    }
}
