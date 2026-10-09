//
//  ReviewSessionService.swift
//  GitlabMenubar
//

import AppKit

/// CLI coding agent that runs an MR review.
enum ReviewAgent: String, CaseIterable, Identifiable {
    case claude
    case opencode
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .opencode: return "opencode"
        case .codex: return "Codex"
        }
    }

    var binary: String { rawValue }

    /// Agent for a project: per-project choice, else the default from Settings.
    static func forProject(_ projectId: Int) -> ReviewAgent {
        let settings = SettingsManager.shared
        let raw = settings.projectReviewAgents[String(projectId)] ?? settings.defaultReviewAgent
        return ReviewAgent(rawValue: raw) ?? .claude
    }
}

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

    /// Session display name/title; also how the app finds the session again.
    var sessionName: String { "Review \(projectName) !\(iid)" }

    var repo: LocalRepoResolver.LocalRepo? {
        LocalRepoResolver.shared.repo(for: projectId, pathWithNamespace: projectPath)
    }

    var agent: ReviewAgent { ReviewAgent.forProject(projectId) }
}

/// A review session for an MR, whichever agent runs it.
struct ReviewSession {
    let agent: ReviewAgent
    /// Claude: short id for `claude attach`/`stop`. opencode: `ses_…` id for `opencode -s`.
    let id: String
    /// Id to continue the conversation: Claude's full session id for `--resume`; opencode's `ses_…` id.
    let resumeId: String
    let cwd: String
    let isWorking: Bool
    /// Process still alive (Claude keeps finished background sessions alive, idle).
    let isAlive: Bool
}

enum ReviewSessionError: LocalizedError {
    case noLocalRepo(projectPath: String, root: String)
    case cliNotFound(agent: ReviewAgent, path: String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noLocalRepo(let path, let root):
            return "No local clone of \(path) in \(root). Set it in Settings → AI reviews."
        case .cliNotFound(let agent, let path):
            return "\(agent.displayName) CLI not found at \(path). Set its path in Settings → AI reviews."
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class ReviewSessionService: ObservableObject {
    static let shared = ReviewSessionService()

    /// Live `claude agents` sessions keyed by name.
    @Published private var claudeSessions: [String: ClaudeAgentEntry] = [:]
    /// Sessions of agents without a session manager (opencode), keyed by session name. Persisted.
    @Published private var storedSessions: [String: StoredSession] = [:]
    private var lastRefresh: Date = .distantPast
    private var resolvedPaths: [ReviewAgent: String] = [:]

    private static let storedSessionsKey = "reviewSessionRecords"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storedSessionsKey),
           let decoded = try? JSONDecoder().decode([String: StoredSession].self, from: data) {
            storedSessions = decoded
        }
    }

    enum StartResult {
        case started
        /// Re-ran the review in the MR's existing session.
        case continued
        case alreadyRunning(ReviewSession)
    }

    // MARK: - Prompts

    /// Prompt sent to Claude, which runs `/review-mr` itself.
    func claudePrompt(for target: ReviewTarget) -> String {
        target.repo?.hasReviewCommand == true ? "/review-mr \(target.iid)" : genericPrompt(for: target)
    }

    /// Text to paste for the target's agent. Claude: `@<repo> /review-mr <iid>`; others: the expanded prompt.
    func pastePrompt(for target: ReviewTarget, agent: ReviewAgent) async -> String {
        switch agent {
        case .claude:
            let handle = target.repo?.handle ?? target.projectPath.split(separator: "/").last.map(String.init) ?? target.projectName
            return "@\(handle) \(claudePrompt(for: target))"
        case .opencode, .codex:
            return await expandedPrompt(for: target, agent: agent, unattended: false)
        }
    }

    func copyPrompt(for target: ReviewTarget, agent: ReviewAgent? = nil) async {
        let text = await pastePrompt(for: target, agent: agent ?? target.agent)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func genericPrompt(for target: ReviewTarget) -> String {
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

    /// The agent's local `/review-mr` command (synced from the Claude one when missing) expanded, else the generic prompt.
    /// Background runs are headless, so nobody can answer a "post this?" question: `unattended` holds all
    /// GitLab writes until the user resumes the session.
    private func expandedPrompt(for target: ReviewTarget, agent: ReviewAgent, unattended: Bool) async -> String {
        var prompt = genericPrompt(for: target)
        if let repo = target.repo,
           let template = AgentCommandSync.reviewTemplate(for: agent, in: repo.url),
           let expanded = await CommandExpander.expand(template, in: repo.url, arguments: String(target.iid)) {
            prompt = expanded
        }
        guard unattended else { return prompt }
        return prompt + """


        IMPORTANT: this session runs unattended. Do NOT post comments, approve, or change anything on \
        GitLab (no `glab mr note`, `glab mr approve` or similar). Write the review here and stop; I will \
        resume this session to read it and confirm what to post.
        """
    }

    // MARK: - Sessions

    func session(for target: ReviewTarget) -> ReviewSession? {
        if let claude = claudeSessions[target.sessionName] {
            return ReviewSession(agent: .claude, id: claude.id ?? claude.sessionId, resumeId: claude.sessionId, cwd: claude.cwd,
                                 isWorking: claude.status == "busy", isAlive: claude.status != nil)
        }
        if let stored = storedSessions[target.sessionName], let id = stored.id {
            let alive = stored.isProcessAlive
            return ReviewSession(agent: stored.agent, id: id, resumeId: id, cwd: stored.cwd, isWorking: alive, isAlive: alive)
        }
        return nil
    }

    func refresh(force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastRefresh) > 3 else { return }
        lastRefresh = Date()
        objectWillChange.send() // stored sessions' "working" state depends on live pids

        guard let claude = try? cliURL(.claude),
              // --all: finished sessions too, so a re-run continues them instead of starting a duplicate.
              let result = try? await Self.run(claude, ["agents", "--json", "--all"], cwd: nil),
              result.status == 0,
              let list = try? JSONDecoder().decode([ClaudeAgentEntry].self, from: Data(result.stdout.utf8)) else {
            return
        }
        // Same name more than once (e.g. duplicates from older versions): keep the most recent.
        claudeSessions = Dictionary(list.map { ($0.name, $0) }, uniquingKeysWith: { a, b in
            (a.startedAt ?? 0) >= (b.startedAt ?? 0) ? a : b
        })
    }

    /// Starts a background review in the project's local repo. If the MR already has a session with this
    /// agent, the review re-runs in it (same conversation, so the agent knows what it reviewed before);
    /// if that session is still working, it's returned to open instead.
    func startReview(for target: ReviewTarget, agent: ReviewAgent? = nil) async throws -> StartResult {
        let agent = agent ?? target.agent
        guard let repo = target.repo else {
            throw ReviewSessionError.noLocalRepo(projectPath: target.projectPath, root: SettingsManager.shared.reposRoot)
        }
        let cli = try cliURL(agent)

        await refresh(force: true)
        let existing = session(for: target).flatMap { $0.agent == agent ? $0 : nil }
        if let existing, existing.isWorking {
            return .alreadyRunning(existing)
        }

        switch agent {
        case .claude:
            try await startClaude(target: target, cli: cli, repo: repo, continuing: existing)
        case .opencode, .codex:
            try await startDetached(agent, target: target, cli: cli, repo: repo, continuing: existing)
        }
        await refresh(force: true)
        return existing == nil ? .started : .continued
    }

    private func startClaude(target: ReviewTarget, cli: URL, repo: LocalRepoResolver.LocalRepo, continuing existing: ReviewSession?) async throws {
        var args = ["--bg", "-n", target.sessionName]
        if let existing {
            // `--resume` on a live session would start a copy: stop it first (the conversation is kept).
            if existing.isAlive {
                _ = try? await Self.run(cli, ["stop", existing.id], cwd: nil)
            }
            args = ["--bg", "--resume", existing.resumeId]
        }
        let result = try await Self.run(cli, args + [claudePrompt(for: target)], cwd: repo.url)
        guard result.status == 0 else {
            let message = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "claude exited with status \(result.status)"
            throw ReviewSessionError.failed(message)
        }
    }

    /// `opencode run` / `codex exec` work in the foreground until the review is done, so they run detached
    /// with their JSON events in a log file; the session id is read from the events.
    private func startDetached(_ agent: ReviewAgent, target: ReviewTarget, cli: URL, repo: LocalRepoResolver.LocalRepo,
                               continuing existing: ReviewSession?) async throws {
        let prompt = await expandedPrompt(for: target, agent: agent, unattended: true)

        let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/GitlabMenubar")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logFile = logDir.appendingPathComponent("\(agent.rawValue)-\(target.projectId)-\(target.iid).jsonl")
        FileManager.default.createFile(atPath: logFile.path, contents: nil)

        let settings = SettingsManager.shared
        var args: [String]
        switch agent {
        case .opencode:
            args = ["run", "--format", "json", "--title", target.sessionName]
            if let existing { args += ["-s", existing.resumeId] }
            let model = settings.opencodeModel.trimmingCharacters(in: .whitespaces)
            if !model.isEmpty { args += ["-m", model] }
            args.append(prompt)
        case .codex:
            // read-only sandbox: the review needs no writes, and Codex's sandbox has no network anyway
            // (the MR data is already in the prompt) — so a background run can't post to GitLab.
            args = ["exec", "--json", "-s", "read-only", "-C", repo.url.path]
            let model = settings.codexModel.trimmingCharacters(in: .whitespaces)
            if !model.isEmpty { args += ["-m", model] }
            if let existing { args += ["resume", existing.resumeId] }
            args.append(prompt)
        case .claude:
            preconditionFailure("Claude runs through `claude --bg`")
        }

        let process = Process()
        process.executableURL = cli
        process.arguments = args
        process.currentDirectoryURL = repo.url
        process.environment = Self.environment()
        process.standardInput = FileHandle.nullDevice
        let log = try FileHandle(forWritingTo: logFile)
        process.standardOutput = log
        process.standardError = log
        let name = target.sessionName
        process.terminationHandler = { _ in
            try? log.close()
            Task { @MainActor in ReviewSessionService.shared.objectWillChange.send() }
        }
        try process.run()

        let previous = storedSessions[name]
        var stored = StoredSession(agent: agent, id: existing?.resumeId, cwd: repo.url.path, pid: process.processIdentifier)
        storedSessions[name] = stored

        // The session id arrives with the first event, usually within a few seconds.
        for _ in 0..<60 {
            if let id = Self.firstSessionId(in: logFile) ?? existing?.resumeId {
                stored.id = id
                storedSessions[name] = stored
                persistStoredSessions()
                return
            }
            if !process.isRunning { break }
            try? await Task.sleep(for: .milliseconds(500))
        }

        storedSessions[name] = previous
        let tail = (try? String(contentsOf: logFile, encoding: .utf8))?.suffix(400) ?? ""
        throw ReviewSessionError.failed("\(agent.displayName) didn't start a session. \(tail)")
    }

    /// Opens the session interactively in a new Terminal window.
    func open(_ session: ReviewSession) {
        guard let cli = try? cliURL(session.agent) else { return }
        let command: String
        switch session.agent {
        case .claude: command = "attach \(Self.shellQuote(session.id))"
        case .opencode: command = "-s \(Self.shellQuote(session.id))"
        // -C: without it Codex asks whether to use the session's folder or the current one.
        case .codex: command = "resume \(Self.shellQuote(session.id)) -C \(Self.shellQuote(session.cwd))"
        }
        let script = """
        #!/bin/zsh -l
        cd \(Self.shellQuote(session.cwd))
        exec \(Self.shellQuote(cli.path)) \(command)
        """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("review-session-\(session.id).command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            print("Failed to open session: \(error)")
        }
    }

    private func persistStoredSessions() {
        if let data = try? JSONEncoder().encode(storedSessions) {
            UserDefaults.standard.set(data, forKey: Self.storedSessionsKey)
        }
    }

    // MARK: - CLI resolution

    private func cliURL(_ agent: ReviewAgent) throws -> URL {
        let settings = SettingsManager.shared
        let configuredPath: String
        switch agent {
        case .claude: configuredPath = settings.claudePath
        case .opencode: configuredPath = settings.opencodePath
        case .codex: configuredPath = settings.codexPath
        }
        let configured = LocalRepoResolver.expand(configuredPath)
        let binary = agent.binary

        var candidates = [configured]
        if let resolved = resolvedPaths[agent] { candidates.append(resolved) }
        // Each tool's own installer location first (opencode v2 installs to ~/.opencode/bin), then package managers.
        let installerDir = agent == .opencode ? "~/.opencode/bin" : "~/.local/bin"
        candidates += ["\(installerDir)/\(binary)", "~/.local/bin/\(binary)", "/opt/homebrew/bin/\(binary)", "/usr/local/bin/\(binary)"]
            .map(LocalRepoResolver.expand)
        if let path = candidates.first(where: { $0.contains("/") && FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        // Installed through a version manager (mise, asdf, nvm…): ask the user's login shell.
        if let path = Self.whichInLoginShell(binary) {
            resolvedPaths[agent] = path
            return URL(fileURLWithPath: path)
        }
        throw ReviewSessionError.cliNotFound(agent: agent, path: configured)
    }

    private static func whichInLoginShell(_ binary: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "command -v \(binary)"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self)
            .split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: - Process helpers

    struct RunResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Finder-launched apps get a minimal PATH; sessions need glab, git, node, etc.
    nonisolated static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = ["\(home)/.local/bin", "\(home)/.local/share/mise/shims", "/opt/homebrew/bin", "/usr/local/bin",
                       env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
            .joined(separator: ":")
        return env
    }

    nonisolated static func run(_ executable: URL, _ arguments: [String], cwd: URL?) async throws -> RunResult {
        try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let cwd { process.currentDirectoryURL = cwd }
            process.environment = environment()

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

    private static func firstSessionId(in logFile: URL) -> String? {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            if let data = line.data(using: .utf8),
               let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = (event["sessionID"] ?? event["thread_id"]) as? String {
                return id
            }
        }
        return nil
    }

    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// An entry of `claude agents --json`.
private struct ClaudeAgentEntry: Decodable {
    let startedAt: Double?
    let id: String?
    let sessionId: String
    let name: String
    let cwd: String
    let status: String?
}

/// A session the app started for an agent without its own session list.
private struct StoredSession: Codable {
    let agentRaw: String
    var id: String?
    let cwd: String
    let pid: Int32

    init(agent: ReviewAgent, id: String?, cwd: String, pid: Int32) {
        self.agentRaw = agent.rawValue
        self.id = id
        self.cwd = cwd
        self.pid = pid
    }

    var agent: ReviewAgent { ReviewAgent(rawValue: agentRaw) ?? .opencode }

    /// Still reviewing while the process the app started is alive.
    var isProcessAlive: Bool { kill(pid, 0) == 0 }
}
