//
//  NotificationService.swift
//  GitlabMenubar
//

import Cocoa
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var timer: Timer?
    private var lastPollDate: Date = .distantPast
    private var isPolling = false

    private override init() {
        super.init()
    }

    // Notification categories / actions for review requests
    private enum Category {
        static let reviewRequest = "REVIEW_REQUEST"
        static let reviewStarted = "REVIEW_STARTED"
    }
    private enum Action {
        static let review = "REVIEW_WITH_CLAUDE"
        static let copyPrompt = "COPY_PROMPT"
        static let openSession = "OPEN_SESSION"
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Notification auth error: \(error)")
            } else {
                print("Notification auth granted: \(granted)")
            }
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
        Task { await tick(force: true) }
    }

    /// Triggers an immediate poll, used when the user opts a project/issue into watching
    /// so the baseline is captured right away instead of waiting for the next tick.
    func pollNow() {
        Task { await tick(force: true) }
    }

    private func tick(force: Bool = false) async {
        guard !isPolling else { return }
        let settings = SettingsManager.shared
        guard settings.notificationsEnabled else { return }
        let interval = TimeInterval(max(5, settings.pollIntervalSeconds))
        guard force || Date().timeIntervalSince(lastPollDate) >= interval else { return }

        isPolling = true
        lastPollDate = Date()
        await poll()
        isPolling = false
    }

    private func poll() async {
        let settings = SettingsManager.shared
        let authService = AuthenticationService()
        guard authService.hasToken else { return }
        let client = GitLabClient(authService: authService)

        guard let me = try? await client.fetchCurrentUser() else { return }

        var projectsById: [Int: GitLabClient.Project] = [:]
        if let starred = try? await client.fetchStarredProjects() {
            projectsById = Dictionary(uniqueKeysWithValues: starred.map { ($0.id, $0) })
        }

        for projectId in settings.watchedProjectIds {
            let project = projectsById[projectId]
            if settings.notifyReviewRequests || settings.autoReviewProjectIds.contains(projectId) {
                await checkReviewRequests(client: client, projectId: projectId, project: project, userId: me.id)
            }
            if settings.notifyAssignedIssues {
                await checkAssignedIssues(client: client, projectId: projectId, project: project, userId: me.id)
            }
            if settings.notifyOwnMRUpdates {
                await checkOwnMRs(client: client, projectId: projectId, project: project, userId: me.id)
            }
        }

        await checkWatchedIssues(client: client, issueKeys: settings.watchedIssueKeys, projectsById: projectsById)
    }

    // MARK: - Checks

    private func checkReviewRequests(client: GitLabClient, projectId: Int, project: GitLabClient.Project?, userId: Int) async {
        guard let mrs = try? await client.fetchProjectMergeRequests(projectId: projectId, reviewerId: userId, state: "opened") else { return }
        let key = "notif_seenReviewMRs_\(projectId)"
        let isFirstRun = UserDefaults.standard.object(forKey: key) == nil
        let seen = seenSet(key)

        if !isFirstRun {
            for mr in mrs where !seen.contains(mr.id) {
                await handleNewReviewRequest(mr: mr, project: project)
            }
        }
        saveSeenSet(key, Set(mrs.map(\.id)))
    }

    /// Starts a review (project's agent) automatically when enabled for the project; otherwise offers it as actions.
    private func handleNewReviewRequest(mr: GitLabClient.MergeRequest, project: GitLabClient.Project?) async {
        guard let project else {
            notify(project: nil, event: "Review req — !\(mr.iid)", body: mr.title, url: mr.webUrl)
            return
        }
        let target = ReviewTarget(project: project, mr: mr)
        let settings = SettingsManager.shared

        if settings.autoReviewProjectIds.contains(project.id) {
            do {
                _ = try await ReviewSessionService.shared.startReview(for: target)
                notify(project: project, event: "Review started — !\(mr.iid)", body: mr.title, url: mr.webUrl,
                       category: Category.reviewStarted, extraInfo: target.userInfo)
                return
            } catch {
                notify(project: project, event: "Review req — !\(mr.iid)",
                       body: "\(mr.title)\nAuto-review failed: \(error.localizedDescription)", url: mr.webUrl,
                       category: Category.reviewRequest, extraInfo: target.userInfo)
                return
            }
        }

        guard settings.notifyReviewRequests else { return }
        notify(project: project, event: "Review req — !\(mr.iid)", body: mr.title, url: mr.webUrl,
               category: Category.reviewRequest, extraInfo: target.userInfo)
    }

    private func checkAssignedIssues(client: GitLabClient, projectId: Int, project: GitLabClient.Project?, userId: Int) async {
        guard let issues = try? await client.fetchProjectIssues(projectId: projectId, assigneeId: userId) else { return }
        let key = "notif_seenAssignedIssues_\(projectId)"
        let isFirstRun = UserDefaults.standard.object(forKey: key) == nil
        let seen = seenSet(key)

        if !isFirstRun {
            for issue in issues where !seen.contains(issue.id) {
                notify(project: project, event: "Assigned — #\(issue.iid)", body: issue.title, url: issue.webUrl)
            }
        }
        saveSeenSet(key, Set(issues.map(\.id)))
    }

    private func checkOwnMRs(client: GitLabClient, projectId: Int, project: GitLabClient.Project?, userId: Int) async {
        guard let mrs = try? await client.fetchProjectMergeRequests(projectId: projectId, scope: "created_by_me", state: "all") else { return }

        let stateKey = "notif_ownMRState_\(projectId)"
        var stateMap = (UserDefaults.standard.dictionary(forKey: stateKey) as? [String: String]) ?? [:]
        let approvalsKey = "notif_ownMRApprovals_\(projectId)"
        var approvalsMap = (UserDefaults.standard.dictionary(forKey: approvalsKey) as? [String: Int]) ?? [:]

        for mr in mrs {
            let idKey = String(mr.id)
            let previousState = stateMap[idKey]
            stateMap[idKey] = mr.state
            if let previousState, previousState != "merged", mr.state == "merged" {
                notify(project: project, event: "Merged — !\(mr.iid)", body: mr.title, url: mr.webUrl)
            }

            guard mr.state == "opened" else { continue }
            guard let approvedBy = try? await client.fetchMergeRequestApprovals(projectId: projectId, mrIid: mr.iid) else { continue }
            let count = approvedBy.count
            let previousCount = approvalsMap[idKey]
            approvalsMap[idKey] = count
            if let previousCount, count > previousCount {
                notify(project: project, event: "Approved — !\(mr.iid)", body: mr.title, url: mr.webUrl)
            }
        }

        UserDefaults.standard.set(stateMap, forKey: stateKey)
        UserDefaults.standard.set(approvalsMap, forKey: approvalsKey)
    }

    private func checkWatchedIssues(client: GitLabClient, issueKeys: Set<String>, projectsById: [Int: GitLabClient.Project]) async {
        let stateKey = "notif_watchedIssueState"
        var stateMap = (UserDefaults.standard.dictionary(forKey: stateKey) as? [String: String]) ?? [:]

        for issueKey in issueKeys {
            let parts = issueKey.split(separator: "#")
            guard parts.count == 2, let projectId = Int(parts[0]), let iid = Int(parts[1]) else { continue }
            guard let issue = try? await client.fetchProjectIssue(projectId: projectId, issueIid: iid) else { continue }

            let currentState = "\(issue.state)|\(issue.assignees?.map(\.username).sorted().joined(separator: ",") ?? "")"
            let previous = stateMap[issueKey]
            stateMap[issueKey] = currentState
            guard let previous, previous != currentState else { continue }
            notify(project: projectsById[projectId], event: "Issue #\(iid) updated", body: "\(issue.title) — \(issue.state)", url: issue.webUrl)
        }

        UserDefaults.standard.set(stateMap, forKey: stateKey)
    }

    // MARK: - Seen-set persistence

    private func seenSet(_ key: String) -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? [])
    }

    private func saveSeenSet(_ key: String, _ set: Set<Int>) {
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    // MARK: - Delivery

    private func registerCategories() {
        let review = UNNotificationAction(identifier: Action.review, title: "Start review")
        let copy = UNNotificationAction(identifier: Action.copyPrompt, title: "Copy prompt")
        let open = UNNotificationAction(identifier: Action.openSession, title: "Open session", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Category.reviewRequest, actions: [review, copy], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.reviewStarted, actions: [open, copy], intentIdentifiers: []),
        ])
    }

    private func notify(project: GitLabClient.Project?, event: String, body: String, url: String,
                        category: String? = nil, extraInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = project.map { "\($0.name) — \(event)" } ?? event
        content.body = body
        content.sound = .default
        content.userInfo = extraInfo.merging(["url": url]) { _, new in new }
        if let category { content.categoryIdentifier = category }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }


    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let reviews = ReviewSessionService.shared

        switch response.actionIdentifier {
        case Action.review:
            if let target = ReviewTarget(userInfo: userInfo) {
                Task {
                    do {
                        if case .alreadyRunning(let session) = try await reviews.startReview(for: target) {
                            reviews.open(session)
                        }
                    } catch {
                        notify(project: nil, event: "Review failed — !\(target.iid)",
                               body: error.localizedDescription, url: target.webUrl)
                    }
                }
            }
        case Action.copyPrompt:
            if let target = ReviewTarget(userInfo: userInfo) {
                Task { await reviews.copyPrompt(for: target) }
            }
        case Action.openSession:
            if let target = ReviewTarget(userInfo: userInfo) {
                Task {
                    await reviews.refresh(force: true)
                    if let session = reviews.session(for: target) {
                        reviews.open(session)
                    }
                }
            }
        default:
            if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}
