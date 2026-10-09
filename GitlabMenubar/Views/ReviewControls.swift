//
//  ReviewControls.swift
//  GitlabMenubar
//

import SwiftUI

/// "Review with <agent>" (or "Open session" when one exists) + "Copy prompt".
/// The review button's menu picks another agent for this MR.
/// `.compact` = icon buttons for list rows, `.full` = labelled buttons for the MR detail.
struct ReviewControls: View {
    enum Style { case compact, full }

    let target: ReviewTarget
    var style: Style = .full

    @ObservedObject private var service = ReviewSessionService.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isStarting = false
    @State private var feedback: String?
    @State private var errorMessage: String?
    @State private var showError = false

    private var session: ReviewSession? { service.session(for: target) }
    private var agent: ReviewAgent { target.agent }
    /// Re-runs go to the agent of the existing session; new reviews use the project's agent.
    private var primaryAgent: ReviewAgent { session?.agent ?? agent }

    var body: some View {
        switch style {
        case .compact: compactBody
        case .full: fullBody
        }
    }

    // MARK: - Compact (list row)

    private var compactBody: some View {
        HStack(spacing: 10) {
            if let session {
                Button { service.open(session) } label: {
                    Image(systemName: "terminal").frame(width: 16, height: 16)
                }
                .help("Open \(session.agent.displayName) session")
            }
            if session?.isWorking != true {
                Menu {
                    agentMenuItems
                } label: {
                    Group {
                        if isStarting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: session == nil ? "sparkles" : "arrow.clockwise")
                        }
                    }
                    .frame(width: 16, height: 16)
                } primaryAction: {
                    start(primaryAgent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(session == nil
                      ? "Review with \(agent.displayName) — hold for other agents"
                      : "Re-run the review in the \(primaryAgent.displayName) session — hold for other agents")
                .disabled(isStarting)
            }

            Button(action: copy) {
                Image(systemName: feedback == "Copied" ? "checkmark" : "doc.on.doc")
                    .frame(width: 16, height: 16)
            }
            .help("Copy prompt")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .popover(isPresented: $showError, arrowEdge: .bottom) {
            Text(errorMessage ?? "")
                .font(.caption)
                .padding(10)
                .frame(width: 240)
        }
    }

    // MARK: - Full (MR detail)

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let session {
                    Button { service.open(session) } label: {
                        Label("Open session", systemImage: "terminal")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
                if session?.isWorking != true {
                    Menu {
                        agentMenuItems
                    } label: {
                        HStack(spacing: 5) {
                            if isStarting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: session == nil ? "sparkles" : "arrow.clockwise")
                            }
                            Text(session == nil ? "Review with \(agent.displayName)" : "Re-run review")
                        }
                        .font(.system(size: 12, weight: .medium))
                    } primaryAction: {
                        start(primaryAgent)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .disabled(isStarting)
                }

                Button(action: copy) {
                    Label(feedback == "Copied" ? "Copied" : "Copy prompt",
                          systemImage: feedback == "Copied" ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let feedback, feedback != "Copied" {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ReviewSessionBadge(target: target)
            }
        }
    }

    @ViewBuilder
    private var agentMenuItems: some View {
        ForEach(ReviewAgent.allCases) { option in
            Button(session?.agent == option ? "Re-run in \(option.displayName) session" : "Review with \(option.displayName)") {
                start(option)
            }
        }
        Divider()
        ForEach(ReviewAgent.allCases) { option in
            Button("Copy prompt for \(option.displayName)") { copy(for: option) }
        }
    }

    // MARK: - Actions

    private func start(_ agent: ReviewAgent) {
        isStarting = true
        errorMessage = nil
        Task {
            do {
                switch try await service.startReview(for: target, agent: agent) {
                case .started:
                    flash(agent == .claude ? "Session started — see claude agents" : "Session started in \(agent.displayName)")
                case .continued:
                    flash("Review re-running in the \(agent.displayName) session")
                case .alreadyRunning(let existing):
                    service.open(existing)
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = style == .compact
            }
            isStarting = false
        }
    }

    private func copy() {
        copy(for: agent)
    }

    private func copy(for agent: ReviewAgent) {
        Task {
            await service.copyPrompt(for: target, agent: agent)
            flash("Copied")
        }
    }

    private func flash(_ message: String) {
        feedback = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if feedback == message { feedback = nil }
        }
    }
}

/// Inline status of the review session for an MR; empty when there is none.
struct ReviewSessionBadge: View {
    let target: ReviewTarget
    @ObservedObject private var service = ReviewSessionService.shared

    var body: some View {
        if let session = service.session(for: target) {
            HStack(spacing: 4) {
                Circle()
                    .fill(session.isWorking ? Color.orange : Color.purple)
                    .frame(width: 5, height: 5)
                Text(session.isWorking ? "Reviewing… (\(session.agent.displayName))" : "\(session.agent.displayName) session open")
                    .foregroundStyle(session.isWorking ? Color.orange : Color.purple)
            }
            .font(.caption)
        }
    }
}

extension View {
    /// Keeps review session state fresh while the view is on screen.
    func refreshesReviewSessions() -> some View {
        task {
            while !Task.isCancelled {
                await ReviewSessionService.shared.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}
