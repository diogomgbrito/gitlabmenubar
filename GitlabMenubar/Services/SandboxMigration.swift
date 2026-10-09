//
//  SandboxMigration.swift
//  GitlabMenubar
//

import Foundation

/// Up to 1.0.0 the app was sandboxed, so its UserDefaults lived in its container.
/// Without the sandbox it reads ~/Library/Preferences instead — copy the old values over once.
enum SandboxMigration {
    private static let doneKey = "migratedFromSandboxContainer"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let containerPlist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleId)/Data/Library/Preferences/\(bundleId).plist")

        guard let data = try? Data(contentsOf: containerPlist),
              let old = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return
        }

        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
