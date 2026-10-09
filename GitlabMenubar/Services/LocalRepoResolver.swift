//
//  LocalRepoResolver.swift
//  GitlabMenubar
//

import Foundation

/// Finds the local clone of a GitLab project by matching each repo's `origin` remote
/// against the project's `path_with_namespace`.
final class LocalRepoResolver {
    static let shared = LocalRepoResolver()

    struct LocalRepo {
        let url: URL
        /// Repo has its own `/review-mr` command.
        let hasReviewCommand: Bool

        /// Handle used in `claude agents` to target the repo, e.g. `@fge-platform`.
        var handle: String { url.lastPathComponent }
    }

    private let queue = DispatchQueue(label: "LocalRepoResolver")
    private var index: [String: URL] = [:]
    private var indexedRoot: String?
    private var lastScan: Date = .distantPast

    func repo(for projectId: Int, pathWithNamespace: String) -> LocalRepo? {
        let settings = SettingsManager.shared
        if let override = settings.repoPathOverrides[String(projectId)] {
            let url = URL(fileURLWithPath: Self.expand(override))
            return FileManager.default.fileExists(atPath: url.path) ? makeRepo(url) : nil
        }

        let root = Self.expand(settings.reposRoot)
        let key = pathWithNamespace.lowercased()
        return queue.sync {
            // Rescan when the root changed, or on a miss at most every 30s (picks up new clones).
            if indexedRoot != root || (index[key] == nil && Date().timeIntervalSince(lastScan) > 30) {
                index = Self.scan(root: root)
                indexedRoot = root
                lastScan = Date()
            }
            return index[key].map(makeRepo)
        }
    }

    private func makeRepo(_ url: URL) -> LocalRepo {
        let commandPaths = [".claude/commands/review-mr.md", ".claude/skills/review-mr/SKILL.md"]
        let hasCommand = commandPaths.contains {
            FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path)
        }
        return LocalRepo(url: url, hasReviewCommand: hasCommand)
    }

    // MARK: - Scanning

    private static func scan(root: String) -> [String: URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var result: [String: URL] = [:]
        for dir in children {
            guard let remote = originURL(of: dir), let path = projectPath(fromRemote: remote) else { continue }
            result[path.lowercased()] = dir
        }
        return result
    }

    /// Reads `[remote "origin"] url` straight from `.git/config` — no `git` process needed.
    private static func originURL(of repo: URL) -> String? {
        let config = repo.appendingPathComponent(".git/config")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return nil }

        var inOrigin = false
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line == "[remote \"origin\"]"
            } else if inOrigin, line.hasPrefix("url") {
                return line.split(separator: "=", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// `https://host/group/sub/repo.git` or `git@host:group/sub/repo.git` → `group/sub/repo`.
    static func projectPath(fromRemote remote: String) -> String? {
        var path: Substring
        if let url = URL(string: remote), url.scheme != nil, url.host != nil {
            path = Substring(url.path)
        } else if let colon = remote.firstIndex(of: ":") {
            path = remote[remote.index(after: colon)...]
        } else {
            return nil
        }
        path = path.drop { $0 == "/" }
        if path.hasSuffix(".git") { path = path.dropLast(4) }
        return path.isEmpty ? nil : String(path)
    }

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
