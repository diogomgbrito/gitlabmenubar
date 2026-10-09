//
//  ClaudeSessionService.swift
//  GitlabMenubar
//

import AppKit

/// The MR a review session is about. Plain values so it can travel through notification userInfo.
struct ReviewTarget {
    let projectId: Int
    let projectName: String
    let projectPath: String
    let iid: Int
    let title: String
    let webUrl: String
    let sourceBranch: String?
    let targetBranch: String?

    init(project: GitLabClient.Project, mr: GitLabClient.MergeRequest) {
        projectId = project.id
        projectName = project.name
        projectPath = project.pathWithNamespace
        iid = mr.iid
        title = mr.title
        webUrl = mr.webUrl
        sourceBranch = mr.sourceBranch
        targetBranch = mr.targetBranch
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let projectId = userInfo["projectId"] as? Int,
              let projectName = userInfo["projectName"] as? String,
              let projectPath = userInfo["projectPath"] as? String,
              let iid = userInfo["iid"] as? Int,
              let title = userInfo["title"] as? String,
              let webUrl = userInfo["url"] as? String else { return nil }
        self.projectId = projectId
        self.projectName = projectName
        self.projectPath = projectPath
        self.iid = iid
        self.title = title
        self.webUrl = webUrl
        self.sourceBranch = userInfo["sourceBranch"] as? String
        self.targetBranch = userInfo["targetBranch"] as? String
    }

    var userInfo: [String: Any] {
        var info: [String: Any] = [
            "projectId": projectId, "projectName": projectName, "projectPath": projectPath,
            "iid": iid, "title": title, "url": webUrl,
        ]
        info["sourceBranch"] = sourceBranch
        info["targetBranch"] = targetBranch
        return info
    }

    /// Session display name; also how the app finds the session again in `claude agents`.
    var sessionName: String { "Review \(projectName) !\(iid)" }

    var repo: LocalRepoResolver.LocalRepo? {
        LocalRepoResolver.shared.repo(for: projectId, pathWithNamespace: projectPath)
    }
}

/// An entry of `claude agents --json`.
struct AgentSession: Decodable {
    let id: String?
    let sessionId: String
    let name: String
    let cwd: String
    let kind: String
    let status: String?

    var isWorking: Bool { status == "busy" }
    var attachId: String { id ?? sessionId }
}

enum ClaudeSessionError: LocalizedError {
    case noLocalRepo(projectPath: String, root: String)
    case claudeNotFound(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noLocalRepo(let path, let root):
            return "No local clone of \(path) in \(root). Set it in Settings → Claude reviews."
        case .claudeNotFound(let path):
            return "Claude CLI not found at \(path). Set its path in Settings → Claude reviews."
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class ClaudeSessionService: ObservableObject {
    static let shared = ClaudeSessionService()

    /// Live sessions keyed by name.
    @Published private(set) var sessions: [String: AgentSession] = [:]
    private var lastRefresh: Date = .distantPast

    enum StartResult {
        case started
        case alreadyRunning(AgentSession)
    }

    // MARK: - Prompts

    func prompt(for target: ReviewTarget) -> String {
        if target.repo?.hasReviewCommand == true {
            return "/review-mr \(target.iid)"
        }
        var branches = ""
        if let source = target.sourceBranch, let dest = target.targetBranch {
            branches = " (\(source) → \(dest))"
        }
        return """
        Review GitLab MR !\(target.iid) "\(target.title)"\(branches): \(target.webUrl). \
        Get the details and diff with `glab mr view \(target.iid) -R \(target.projectPath)` and \
        `glab mr diff \(target.iid) -R \(target.projectPath)`. Report blockers, should-fix and optional \
        findings. Don't post anything to GitLab without asking me first.
        """
    }

    /// Text to paste into `claude agents`: `@<repo> <prompt>`.
    func pastePrompt(for target: ReviewTarget) -> String {
        let handle = target.repo?.handle ?? target.projectPath.split(separator: "/").last.map(String.init) ?? target.projectName
        return "@\(handle) \(prompt(for: target))"
    }

    func copyPrompt(for target: ReviewTarget) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pastePrompt(for: target), forType: .string)
    }

    // MARK: - Sessions

    func session(for target: ReviewTarget) -> AgentSession? {
        sessions[target.sessionName]
    }

    func refresh(force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastRefresh) > 3 else { return }
        lastRefresh = Date()
        guard let claude = try? claudeURL(),
              let result = try? await Self.run(claude, ["agents", "--json"], cwd: nil),
              result.status == 0,
              let list = try? JSONDecoder().decode([AgentSession].self, from: Data(result.stdout.utf8)) else {
            return
        }
        sessions = Dictionary(list.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Starts a background `claude --bg` session in the project's local repo, unless one is already running.
    func startReview(for target: ReviewTarget) async throws -> StartResult {
        guard let repo = target.repo else {
            throw ClaudeSessionError.noLocalRepo(projectPath: target.projectPath, root: SettingsManager.shared.reposRoot)
        }
        let claude = try claudeURL()

        await refresh(force: true)
        if let existing = session(for: target) {
            return .alreadyRunning(existing)
        }

        let result = try await Self.run(claude, ["--bg", "-n", target.sessionName, prompt(for: target)], cwd: repo.url)
        guard result.status == 0 else {
            let message = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "claude exited with status \(result.status)"
            throw ClaudeSessionError.failed(message)
        }

        await refresh(force: true)
        return .started
    }

    /// Opens the session in a new Terminal window via `claude attach`.
    func open(_ session: AgentSession) {
        guard let claude = try? claudeURL() else { return }
        let script = """
        #!/bin/zsh -l
        cd \(Self.shellQuote(session.cwd))
        exec \(Self.shellQuote(claude.path)) attach \(Self.shellQuote(session.attachId))
        """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("claude-attach-\(session.attachId).command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            print("Failed to open session: \(error)")
        }
    }

    // MARK: - Process helpers

    private func claudeURL() throws -> URL {
        let configured = LocalRepoResolver.expand(SettingsManager.shared.claudePath)
        let candidates = [configured, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ClaudeSessionError.claudeNotFound(configured)
        }
        return URL(fileURLWithPath: path)
    }

    private struct RunResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static func run(_ executable: URL, _ arguments: [String], cwd: URL?) async throws -> RunResult {
        try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let cwd { process.currentDirectoryURL = cwd }

            // Finder-launched apps get a minimal PATH; the session needs glab, git, node, etc.
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
                .joined(separator: ":")
            process.environment = env

            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice

            try process.run()
            let stdout = out.fileHandleForReading.readDataToEndOfFile()
            let stderr = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return RunResult(
                status: process.terminationStatus,
                stdout: String(decoding: stdout, as: UTF8.self),
                stderr: String(decoding: stderr, as: UTF8.self)
            )
        }.value
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
