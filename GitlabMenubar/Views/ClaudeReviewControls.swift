//
//  ClaudeReviewControls.swift
//  GitlabMenubar
//

import SwiftUI

/// "Review with Claude" (or "Open session" when one is running) + "Copy prompt".
/// `.compact` = icon buttons for list rows, `.full` = labelled buttons for the MR detail.
struct ClaudeReviewControls: View {
    enum Style { case compact, full }

    let target: ReviewTarget
    var style: Style = .full

    @ObservedObject private var service = ClaudeSessionService.shared
    @State private var isStarting = false
    @State private var feedback: String?
    @State private var errorMessage: String?
    @State private var showError = false

    private var session: AgentSession? { service.session(for: target) }

    var body: some View {
        switch style {
        case .compact: compactBody
        case .full: fullBody
        }
    }

    // MARK: - Compact (list row)

    private var compactBody: some View {
        HStack(spacing: 10) {
            Button(action: primaryAction) {
                Group {
                    if isStarting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: session == nil ? "sparkles" : "terminal")
                    }
                }
                .frame(width: 16, height: 16)
            }
            .help(session == nil ? "Review with Claude" : "Open Claude session")
            .disabled(isStarting)
            .popover(isPresented: $showError, arrowEdge: .bottom) {
                Text(errorMessage ?? "")
                    .font(.caption)
                    .padding(10)
                    .frame(width: 240)
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
    }

    // MARK: - Full (MR detail)

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: primaryAction) {
                    HStack(spacing: 5) {
                        if isStarting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: session == nil ? "sparkles" : "terminal")
                        }
                        Text(session == nil ? "Review with Claude" : "Open session")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .disabled(isStarting)

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
                ClaudeSessionBadge(target: target)
            }
        }
    }

    // MARK: - Actions

    private func primaryAction() {
        if let session {
            service.open(session)
            return
        }
        isStarting = true
        errorMessage = nil
        Task {
            do {
                switch try await service.startReview(for: target) {
                case .started:
                    flash("Session started — see claude agents")
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
        service.copyPrompt(for: target)
        flash("Copied")
    }

    private func flash(_ message: String) {
        feedback = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if feedback == message { feedback = nil }
        }
    }
}

/// Inline status of the Claude session for an MR; empty when there is none.
struct ClaudeSessionBadge: View {
    let target: ReviewTarget
    @ObservedObject private var service = ClaudeSessionService.shared

    var body: some View {
        if let session = service.session(for: target) {
            HStack(spacing: 4) {
                Circle()
                    .fill(session.isWorking ? Color.orange : Color.purple)
                    .frame(width: 5, height: 5)
                Text(session.isWorking ? "Reviewing…" : "Claude session open")
                    .foregroundStyle(session.isWorking ? Color.orange : Color.purple)
            }
            .font(.caption)
        }
    }
}

extension View {
    /// Keeps `claude agents` state fresh while the view is on screen.
    func refreshesClaudeSessions() -> some View {
        task {
            while !Task.isCancelled {
                await ClaudeSessionService.shared.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}
