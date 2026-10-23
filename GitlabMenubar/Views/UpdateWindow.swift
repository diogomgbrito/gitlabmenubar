//
//  UpdateWindow.swift
//  GitlabMenubar
//

import AppKit
import SwiftUI
import WebKit

/// Standalone "new version available" window with the release notes (Sparkle-style).
@MainActor
final class UpdateWindowController {
    static let shared = UpdateWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Software Update"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 480, height: 360)
            window.contentViewController = NSHostingController(rootView: UpdateView { [weak self] in self?.close() })
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

struct UpdateView: View {
    @ObservedObject private var updates = UpdateService.shared
    @ObservedObject private var settings = SettingsManager.shared
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("A new version of GitlabMenubar is available!")
                        .font(.system(size: 14, weight: .bold))
                    Text("GitlabMenubar \(updates.availableVersion ?? "") is now available—you have \(updates.currentVersion). Would you like to \(updates.brewURL == nil ? "download" : "install") it now?")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ReleaseNotesView(html: releaseNotesHTML)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))

            Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                .font(.system(size: 12))

            if updates.isUpdating {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing \(updates.availableVersion ?? "the update")… GitlabMenubar restarts when it's done.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(minHeight: 32)
            } else if updates.updateFailed {
                HStack {
                    Text(updates.lastError ?? "The update failed.")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Show Log") { updates.showLog() }
                    Button("Update in Terminal") {
                        updates.upgradeInTerminal()
                        close()
                    }
                    .keyboardShortcut(.defaultAction)
                    .help("Run \(UpdateService.upgradeCommand) in Terminal")
                }
                .controlSize(.large)
            } else {
                HStack {
                    Button("Skip This Version") {
                        updates.skip()
                        close()
                    }
                    Spacer()
                    Button("Remind Me Later") {
                        close()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(updates.brewURL == nil ? "Download Update" : "Install Update") {
                        updates.upgrade()
                        if updates.brewURL == nil { close() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .help(updates.brewURL == nil ? "Open the release page" : "Install with Homebrew and restart")
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    /// Notes of every version since the installed one, newest first.
    private var releaseNotesHTML: String {
        updates.newerReleases.map { release in
            let date = release.publishedDate.map { " (\($0.formatted(date: .long, time: .omitted)))" } ?? ""
            return "<h1>v\(release.version)\(date)</h1>\n\(release.bodyHtml ?? "")"
        }
        .joined(separator: "\n")
    }
}

/// GitHub's rendered release notes in a web view; links open in the browser.
private struct ReleaseNotesView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(Self.page(html), baseURL: URL(string: "https://github.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private static func page(_ body: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; }
          body { font: 13px -apple-system, sans-serif; line-height: 1.45; margin: 14px 16px; background: transparent; }
          h1 { font-size: 20px; margin: 18px 0 8px; }
          h1:first-child { margin-top: 0; }
          h2 { font-size: 15px; margin: 14px 0 6px; }
          h3 { font-size: 13px; margin: 12px 0 4px; }
          p, ul, ol { margin: 6px 0; }
          ul, ol { padding-left: 22px; }
          a { color: -apple-system-control-accent; }
          code { font: 12px ui-monospace, monospace; background: rgba(127,127,127,0.15); padding: 1px 4px; border-radius: 4px; }
          table { border-collapse: collapse; margin: 8px 0; }
          th, td { border: 1px solid rgba(127,127,127,0.3); padding: 4px 8px; text-align: left; vertical-align: top; }
          img { max-width: 100%; }
        </style></head>
        <body>\(body)</body></html>
        """
    }
}
