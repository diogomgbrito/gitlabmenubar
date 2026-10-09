//
//  AgentCommandSync.swift
//  GitlabMenubar
//

import Foundation

/// Keeps a local copy of the repo's Claude `/review-mr` command for other agents, so they can re-run the
/// review when the user resumes a session: opencode gets a command (`.opencode/commands/review-mr.md`,
/// same `$ARGUMENTS`/`` !`cmd` `` syntax), Codex a skill (`.agents/skills/review-mr/SKILL.md`, plain
/// instructions — Codex has no repo-level commands). A file the user wrote is never touched; generated
/// copies are git-excluded and refreshed when the Claude original changes.
enum AgentCommandSync {
    private static let marker = "generated-by: GitlabMenubar"
    /// Bump when `convert` changes so existing generated copies are rewritten.
    private static let formatVersion = 3
    private static var header: String { "\(marker) (format \(formatVersion))" }

    private static let claudeCommand = ".claude/commands/review-mr.md"

    /// Review template with `$ARGUMENTS`/`` !`cmd` `` syntax for headless runs, syncing the agent's local copy
    /// on the way. nil when the repo has no review command.
    static func reviewTemplate(for agent: ReviewAgent, in repo: URL) -> String? {
        let original = try? String(contentsOf: repo.appendingPathComponent(claudeCommand), encoding: .utf8)
        switch agent {
        case .claude:
            return original
        case .opencode:
            return sync(into: ".opencode/commands/review-mr.md", in: repo, render: convert)
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        case .codex:
            _ = sync(into: ".agents/skills/review-mr/SKILL.md", in: repo, render: convertToSkill)
            return original.map(convert)
        }
    }

    private static func sync(into relativePath: String, in repo: URL, render: (String) -> String) -> URL? {
        let fm = FileManager.default
        let source = repo.appendingPathComponent(claudeCommand)
        let target = repo.appendingPathComponent(relativePath)

        if let existing = try? String(contentsOf: target, encoding: .utf8) {
            // The user's own command: use as is.
            guard existing.contains(marker) else { return target }
            // Our copy: keep unless the Claude original or the conversion changed.
            if existing.contains(header) && !isNewer(source, than: target) { return target }
        }

        guard let original = try? String(contentsOf: source, encoding: .utf8) else {
            return fm.fileExists(atPath: target.path) ? target : nil
        }

        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try render(original).write(to: target, atomically: true, encoding: .utf8)
            excludeFromGit(relativePath, in: repo)
            return target
        } catch {
            print("AgentCommandSync: failed to write \(target.path): \(error)")
            return nil
        }
    }

    /// Claude frontmatter → opencode: keep `description`, drop Claude-only fields (`model: opus`,
    /// `allowed-tools`, `argument-hint`, `effort`). `$ARGUMENTS` and `` !`cmd` `` are shared syntax.
    /// `glab … -R <group/project>` becomes `-R "$(git remote get-url origin)"` so the copy works in any
    /// clone — glab can't always infer the project itself (404s on self-hosted instances).
    private static func convert(_ claudeCommand: String) -> String {
        let (description, body) = split(claudeCommand)
        return """
        ---
        description: \(description)
        # \(header) from \(Self.claudeCommand) — edits are overwritten; remove this line to keep your own version.
        ---
        \(repoStep + genericGlabRepo(body))
        """
    }

    /// Codex skill: skills are plain instructions the model follows, so `` !`cmd` `` becomes "run `cmd`"
    /// and `$ARGUMENTS` the MR number the user asks about.
    private static func convertToSkill(_ claudeCommand: String) -> String {
        let (description, body) = split(claudeCommand)
        var instructions = repoStep + genericGlabRepo(body)
        if let injection = try? NSRegularExpression(pattern: #"!`([^`]+)`"#) {
            instructions = injection.stringByReplacingMatches(
                in: instructions, range: NSRange(instructions.startIndex..., in: instructions), withTemplate: "run `$1`")
        }
        instructions = instructions.replacingOccurrences(of: "$ARGUMENTS", with: "<MR>")
        let oneLine = description.replacingOccurrences(of: "\"", with: "'")
        return """
        ---
        name: review-mr
        description: "\(oneLine) Use when asked to review a GitLab MR by number."
        # \(header) from \(Self.claudeCommand) — edits are overwritten; remove this line to keep your own version.
        ---

        The user names the MR to review, e.g. "review MR 42" — `<MR>` below is that number.
        \(instructions)
        """
    }

    /// Frontmatter `description` and the body after the frontmatter.
    private static func split(_ command: String) -> (description: String, body: String) {
        var description = "Review a GitLab MR"
        var body = command
        if command.hasPrefix("---") {
            let lines = command.split(separator: "\n", omittingEmptySubsequences: false)
            if let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                if let line = lines[1..<end].first(where: { $0.hasPrefix("description:") }) {
                    description = line.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
                }
                body = lines[(end + 1)...].joined(separator: "\n")
            }
        }
        return (description, body)
    }

    static let repoFlag = #"-R "$(git remote get-url origin)""#

    /// Shown first, so the agent also targets the right repo in glab commands it runs itself.
    private static let repoStep = """

    ## Step 0 — Repository

    GitLab project for this repo: !`git remote get-url origin`
    Run every `glab` command with `\(repoFlag)` so it targets this project.

    """

    /// Replaces `-R <path>` / `--repo <path>` on glab lines with the repo's own remote.
    static func genericGlabRepo(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s(?:-R|--repo)[ =][^\s`'"]+"#) else { return text }
        let template = NSRegularExpression.escapedTemplate(for: " " + repoFlag)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let line = String(line)
            guard line.contains("glab ") else { return line }
            return regex.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: template)
        }.joined(separator: "\n")
    }

    private static func isNewer(_ a: URL, than b: URL) -> Bool {
        let date = { (url: URL) in (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast }
        return date(a) > date(b)
    }

    /// Adds the path to `.git/info/exclude` so the generated file never shows up in `git status`.
    private static func excludeFromGit(_ relativePath: String, in repo: URL) {
        let gitDir = repo.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir), isDir.boolValue else { return }

        let exclude = gitDir.appendingPathComponent("info/exclude")
        let entry = "/" + relativePath
        let current = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
        guard !current.split(separator: "\n").contains(where: { $0 == entry }) else { return }

        try? FileManager.default.createDirectory(at: exclude.deletingLastPathComponent(), withIntermediateDirectories: true)
        let updated = current + (current.isEmpty || current.hasSuffix("\n") ? "" : "\n") + entry + "\n"
        try? updated.write(to: exclude, atomically: true, encoding: .utf8)
    }
}
