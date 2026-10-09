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
