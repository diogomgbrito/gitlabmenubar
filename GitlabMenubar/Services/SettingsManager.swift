//
//  SettingsManager.swift
//  GitlabMenubar
//
//  Created by Antigravity on 18/12/2025.
//

import Foundation

class SettingsManager: ObservableObject {
    // Shared instance so background services (e.g. NotificationService) observe
    // the same settings the UI writes to, instead of a stale per-view copy.
    static let shared = SettingsManager()

    @Published var activeTimeMonths: Int {
        didSet {
            UserDefaults.standard.set(activeTimeMonths, forKey: "activeTimeMonths")
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }

    @Published var notifyReviewRequests: Bool {
        didSet {
            UserDefaults.standard.set(notifyReviewRequests, forKey: "notifyReviewRequests")
        }
    }

    @Published var notifyAssignedIssues: Bool {
        didSet {
            UserDefaults.standard.set(notifyAssignedIssues, forKey: "notifyAssignedIssues")
        }
    }

    @Published var notifyOwnMRUpdates: Bool {
        didSet {
            UserDefaults.standard.set(notifyOwnMRUpdates, forKey: "notifyOwnMRUpdates")
        }
    }

    @Published var pollIntervalSeconds: Int {
        didSet {
            UserDefaults.standard.set(pollIntervalSeconds, forKey: "pollIntervalSeconds")
        }
    }

    /// Projects the user explicitly opted into for background notifications.
    @Published var watchedProjectIds: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(watchedProjectIds), forKey: "watchedProjectIds")
        }
    }

    /// Individual issues watched regardless of assignment, keyed "projectId#iid".
    @Published var watchedIssueKeys: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(watchedIssueKeys), forKey: "watchedIssueKeys")
        }
    }

    // MARK: Claude reviews

    /// Folder scanned for local clones of GitLab projects (one level deep).
    @Published var reposRoot: String {
        didSet {
            UserDefaults.standard.set(reposRoot, forKey: "reposRoot")
        }
    }

    /// Path to the `claude` CLI. Apps launched from Finder don't inherit the shell PATH.
    @Published var claudePath: String {
        didSet {
            UserDefaults.standard.set(claudePath, forKey: "claudePath")
        }
    }

    /// Manual project → local repo mapping, keyed by GitLab project id (as String).
    @Published var repoPathOverrides: [String: String] {
        didSet {
            UserDefaults.standard.set(repoPathOverrides, forKey: "repoPathOverrides")
        }
    }

    /// Default agent for reviews (`ReviewAgent` raw value).
    @Published var defaultReviewAgent: String {
        didSet {
            UserDefaults.standard.set(defaultReviewAgent, forKey: "defaultReviewAgent")
        }
    }

    /// Per-project agent choice, keyed by GitLab project id (as String). Missing = default.
    @Published var projectReviewAgents: [String: String] {
        didSet {
            UserDefaults.standard.set(projectReviewAgents, forKey: "projectReviewAgents")
        }
    }

    /// Path to the `opencode` CLI; a bare name is resolved through the login shell.
    @Published var opencodePath: String {
        didSet {
            UserDefaults.standard.set(opencodePath, forKey: "opencodePath")
        }
    }

    /// `provider/model` passed to `opencode run -m`; empty = opencode's default.
    @Published var opencodeModel: String {
        didSet {
            UserDefaults.standard.set(opencodeModel, forKey: "opencodeModel")
        }
    }

    /// Path to the `codex` CLI; a bare name is resolved through the login shell.
    @Published var codexPath: String {
        didSet {
            UserDefaults.standard.set(codexPath, forKey: "codexPath")
        }
    }

    /// Model passed to `codex exec -m`; empty = Codex's default.
    @Published var codexModel: String {
        didSet {
            UserDefaults.standard.set(codexModel, forKey: "codexModel")
        }
    }

    /// Projects where a review request starts a review session automatically.
    @Published var autoReviewProjectIds: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(autoReviewProjectIds), forKey: "autoReviewProjectIds")
        }
    }

    init() {
        let savedValue = UserDefaults.standard.integer(forKey: "activeTimeMonths")
        // If no value saved (returns 0), use default of 1
        self.activeTimeMonths = savedValue > 0 ? savedValue : 1

        let defaults = UserDefaults.standard
        self.notificationsEnabled = defaults.object(forKey: "notificationsEnabled") == nil ? true : defaults.bool(forKey: "notificationsEnabled")
        self.notifyReviewRequests = defaults.object(forKey: "notifyReviewRequests") == nil ? true : defaults.bool(forKey: "notifyReviewRequests")
        self.notifyAssignedIssues = defaults.object(forKey: "notifyAssignedIssues") == nil ? true : defaults.bool(forKey: "notifyAssignedIssues")
        self.notifyOwnMRUpdates = defaults.object(forKey: "notifyOwnMRUpdates") == nil ? true : defaults.bool(forKey: "notifyOwnMRUpdates")
        let savedInterval = defaults.integer(forKey: "pollIntervalSeconds")
        self.pollIntervalSeconds = savedInterval > 0 ? savedInterval : 300
        self.watchedProjectIds = Set(defaults.array(forKey: "watchedProjectIds") as? [Int] ?? [])
        self.watchedIssueKeys = Set(defaults.array(forKey: "watchedIssueKeys") as? [String] ?? [])
        self.reposRoot = defaults.string(forKey: "reposRoot") ?? "~/brilean/git"
        self.claudePath = defaults.string(forKey: "claudePath") ?? "~/.local/bin/claude"
        self.repoPathOverrides = defaults.dictionary(forKey: "repoPathOverrides") as? [String: String] ?? [:]
        self.autoReviewProjectIds = Set(defaults.array(forKey: "autoReviewProjectIds") as? [Int] ?? [])
        self.defaultReviewAgent = defaults.string(forKey: "defaultReviewAgent") ?? "claude"
        self.projectReviewAgents = defaults.dictionary(forKey: "projectReviewAgents") as? [String: String] ?? [:]
        self.opencodePath = defaults.string(forKey: "opencodePath") ?? "opencode"
        self.opencodeModel = defaults.string(forKey: "opencodeModel") ?? ""
        self.codexPath = defaults.string(forKey: "codexPath") ?? "codex"
        self.codexModel = defaults.string(forKey: "codexModel") ?? ""
    }

    func toggleAutoReview(_ id: Int) {
        if autoReviewProjectIds.contains(id) {
            autoReviewProjectIds.remove(id)
        } else {
            autoReviewProjectIds.insert(id)
        }
    }

    func isProjectWatched(_ id: Int) -> Bool {
        watchedProjectIds.contains(id)
    }

    func toggleProjectWatch(_ id: Int) {
        if watchedProjectIds.contains(id) {
            watchedProjectIds.remove(id)
        } else {
            watchedProjectIds.insert(id)
        }
    }

    func isIssueWatched(projectId: Int, iid: Int) -> Bool {
        watchedIssueKeys.contains("\(projectId)#\(iid)")
    }

    func toggleIssueWatch(projectId: Int, iid: Int) {
        let key = "\(projectId)#\(iid)"
        if watchedIssueKeys.contains(key) {
            watchedIssueKeys.remove(key)
        } else {
            watchedIssueKeys.insert(key)
        }
    }
}
