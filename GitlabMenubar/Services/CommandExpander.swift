//
//  CommandExpander.swift
//  GitlabMenubar
//

import Foundation

/// Expands a slash command file (Claude/opencode syntax) into a plain prompt, for headless runs that
/// can't invoke commands: drops the frontmatter, substitutes `$ARGUMENTS`, and replaces each
/// `` !`cmd` `` with the command's output (run in the repo, like the agents do).
enum CommandExpander {
    /// Output cap per command, so a huge diff can't blow past the argument size limit.
    private static let maxOutputBytes = 150_000

    static func expand(_ raw: String, in repo: URL, arguments: String) async -> String? {
        let body = stripFrontmatter(raw).replacingOccurrences(of: "$ARGUMENTS", with: arguments)
        return await expandShellInjections(body, cwd: repo)
    }

    private static func stripFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return text
        }
        return lines[(end + 1)...].joined(separator: "\n")
    }

    private static func expandShellInjections(_ text: String, cwd: URL) async -> String {
        guard let regex = try? NSRegularExpression(pattern: #"!`([^`]+)`"#) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var result = text
        // Replace from the end so earlier ranges stay valid.
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let commandRange = Range(match.range(at: 1), in: result) else { continue }
            let output = await run(String(result[commandRange]), cwd: cwd)
            result.replaceSubrange(whole, with: output)
        }
        return result
    }

    private static func run(_ command: String, cwd: URL) async -> String {
        guard let result = try? await ReviewSessionService.run(
            URL(fileURLWithPath: "/bin/zsh"), ["-lc", command], cwd: cwd
        ) else {
            return "(failed to run: \(command))"
        }
        var output = result.stdout + result.stderr
        if output.utf8.count > maxOutputBytes {
            output = String(output.prefix(maxOutputBytes)) + "\n… (output truncated)"
        }
        return output.trimmingCharacters(in: .newlines)
    }
}
