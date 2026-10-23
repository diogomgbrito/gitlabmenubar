//
//  UpdateService.swift
//  GitlabMenubar
//

import AppKit
import Foundation

/// Checks GitHub Releases for a newer version. The app ships as a Homebrew cask in its own tap,
/// so an update is `brew upgrade --cask`, run in the background (Terminal as a fallback).
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    static let upgradeCommand = "brew update && brew upgrade --cask gitlab-menubar"
    private static let releasesURL = URL(string: "https://api.github.com/repos/diogomgbrito/gitlabmenubar/releases?per_page=20")!
    private static let releasesPage = URL(string: "https://github.com/diogomgbrito/gitlabmenubar/releases/latest")!
    private static let checkInterval: Duration = .seconds(6 * 3600)
    private static let skippedVersionKey = "skippedUpdateVersion"
    private static let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/GitlabMenubar/update.log")

    struct Release: Decodable, Identifiable {
        let tagName: String
        let htmlUrl: String
        /// GitHub-rendered release notes (requested with the `html+json` media type).
        let bodyHtml: String?
        let publishedAt: String?
        let draft: Bool
        let prerelease: Bool

        var id: String { tagName }
        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
        var publishedDate: Date? { publishedAt.flatMap { try? Date($0, strategy: .iso8601) } }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case bodyHtml = "body_html"
            case publishedAt = "published_at"
            case draft
            case prerelease
        }
    }

    /// Releases newer than the running version, newest first.
    @Published private(set) var newerReleases: [Release] = []
    @Published private(set) var isChecking = false
    /// Background `brew upgrade` running (see `upgrade()`).
    @Published private(set) var isUpdating = false
    @Published private(set) var updateFailed = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastChecked: Date?
    /// "Skip This Version": no window or banner for it; a manual check still shows it.
    @Published private(set) var skippedVersion: String? = UserDefaults.standard.string(forKey: skippedVersionKey)

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    private var loop: Task<Void, Never>?

    var availableVersion: String? { newerReleases.first?.version }

    var showsBanner: Bool {
        availableVersion != nil && availableVersion != skippedVersion
    }

    /// `brew` of the prefix where the cask is installed; nil when the app wasn't installed with Homebrew.
    var brewURL: URL? {
        ["/opt/homebrew", "/usr/local"]
            .first { FileManager.default.fileExists(atPath: "\($0)/Caskroom/gitlab-menubar") && FileManager.default.isExecutableFile(atPath: "\($0)/bin/brew") }
            .map { URL(fileURLWithPath: "\($0)/bin/brew") }
    }

    func start() {
        loop?.cancel()
        loop = Task {
            while !Task.isCancelled {
                if SettingsManager.shared.checkForUpdates {
                    await check()
                }
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    /// Background checks open the update window for a new, non-skipped version; a manual check
    /// (`userInitiated`) always shows the result, including "up to date" and errors.
    func check(userInitiated: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: Self.releasesURL)
        request.setValue("application/vnd.github.html+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            newerReleases = releases
                .filter { !$0.draft && !$0.prerelease && Self.isVersion($0.version, newerThan: currentVersion) }
                .sorted { Self.isVersion($0.version, newerThan: $1.version) }
            lastError = nil
            lastChecked = Date()
        } catch {
            lastError = "Couldn't check for updates: \(error.localizedDescription)"
            if userInitiated { showAlert("Couldn't check for updates", error.localizedDescription) }
            return
        }

        if let version = availableVersion, userInitiated || version != skippedVersion {
            UpdateWindowController.shared.show()
        } else if userInitiated {
            showAlert("You're up to date", "GitlabMenubar \(currentVersion) is the latest version.")
        }
    }

    func skip() {
        skippedVersion = availableVersion
        UserDefaults.standard.set(availableVersion, forKey: Self.skippedVersionKey)
    }

    /// Runs the upgrade in the background: `--yes` skips Homebrew's confirmation and `--no-quit` keeps this
    /// app running while the cask replaces it; on success the app relaunches into the new version.
    func upgrade() {
        guard let brew = brewURL else {
            NSWorkspace.shared.open(newerReleases.first.flatMap { URL(string: $0.htmlUrl) } ?? Self.releasesPage)
            return
        }
        guard !isUpdating, let version = availableVersion else { return }
        isUpdating = true
        updateFailed = false
        lastError = nil

        try? FileManager.default.createDirectory(at: Self.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.logFile.path, contents: nil)

        let brewPath = ReviewSessionService.shellQuote(brew.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "\(brewPath) update && HOMEBREW_NO_AUTO_UPDATE=1 \(brewPath) upgrade --cask --yes --no-quit gitlab-menubar"]
        var env = ReviewSessionService.environment()
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env
        // No stdin: an unexpected prompt fails the run instead of hanging it.
        process.standardInput = FileHandle.nullDevice
        do {
            let log = try FileHandle(forWritingTo: Self.logFile)
            process.standardOutput = log
            process.standardError = log
            process.terminationHandler = { process in
                try? log.close()
                let status = process.terminationStatus
                Task { @MainActor in UpdateService.shared.finishUpgrade(status: status, version: version, brew: brew) }
            }
            try process.run()
        } catch {
            isUpdating = false
            updateFailed = true
            lastError = "Couldn't start the update: \(error.localizedDescription)"
        }
    }

    private func finishUpgrade(status: Int32, version: String, brew: URL) {
        let prefix = brew.deletingLastPathComponent().deletingLastPathComponent()
        let installed = FileManager.default.fileExists(atPath: prefix.appendingPathComponent("Caskroom/gitlab-menubar/\(version)").path)
        guard status == 0, installed else {
            isUpdating = false
            updateFailed = true
            lastError = status == 0 ? "Homebrew didn't install \(version)." : "Homebrew exited with status \(status)."
            return
        }
        // Relaunch from a separate process once this one has quit.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; open \(ReviewSessionService.shellQuote(installedAppPath))"]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    func showLog() {
        NSWorkspace.shared.open(Self.logFile)
    }

    /// Fallback when the background run fails: the same upgrade in a Terminal window, where prompts
    /// can be answered. The cask quits this app before replacing it; the script reopens it, then waits
    /// for Enter and closes its window.
    func upgradeInTerminal() {
        guard let brew = brewURL else { return }
        let brewPath = ReviewSessionService.shellQuote(brew.path)
        let appPath = ReviewSessionService.shellQuote(installedAppPath)
        let script = """
        #!/bin/zsh -l
        clear
        echo "Updating GitlabMenubar \(currentVersion) → \(availableVersion ?? "latest")…"
        echo
        \(brewPath) update && HOMEBREW_NO_AUTO_UPDATE=1 \(brewPath) upgrade --cask --yes gitlab-menubar
        update_status=$?
        open \(appPath)
        echo
        if (( update_status == 0 )); then
          echo "✓ GitlabMenubar updated."
        else
          echo "✗ Update failed (exit $update_status). You can retry with: \(Self.upgradeCommand)"
        fi
        read -r "?Press Enter to close this window."
        # Close this window even if the Terminal profile keeps windows open after the shell exits.
        this_tty=$(tty)
        (sleep 0.5; osascript -e "tell application \\"Terminal\\" to repeat with w in windows
          if tty of selected tab of w is \\"$this_tty\\" then close w
        end repeat" >/dev/null 2>&1) &!
        exit 0
        """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("gitlabmenubar-update.command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            lastError = "Couldn't start the update: \(error.localizedDescription)"
        }
    }

    /// The cask's app (a debug build runs from DerivedData, but brew replaces the one in Applications).
    private var installedAppPath: String {
        let bundle = Bundle.main.bundleURL
        return bundle.deletingLastPathComponent().lastPathComponent == "Applications" ? bundle.path : "/Applications/GitlabMenubar.app"
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    nonisolated static func isVersion(_ version: String, newerThan other: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = other.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
