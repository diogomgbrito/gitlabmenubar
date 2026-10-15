//
//  AppDelegate.swift
//  GitlabMenubar
//
//  Created by Diogo Brito on 16/12/2025.
//

import Cocoa
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    /// Main popover content, kept between openings to restore the last visited page.
    private var mainController: NSHostingController<ContentView>?
    private var hotkeySetting: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SandboxMigration.run()

        // Create the status item in the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            }
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Create the popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 380, height: 500)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: ContentView())

        NotificationService.shared.start()

        GlobalHotkey.shared.onPress = { [weak self] in self?.toggleFromHotkey() }
        hotkeySetting = SettingsManager.shared.$globalHotkeyEnabled.sink { enabled in
            if enabled {
                GlobalHotkey.shared.register()
            } else {
                GlobalHotkey.shared.unregister()
            }
        }
    }

    private func toggleFromHotkey() {
        guard let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showMainContent(fromRoot: false)
        }
    }

    @objc func togglePopover(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Right-click: show menu
            showContextMenu(for: sender)
        } else {
            // Left-click: toggle popover with main content
            if let popover = popover {
                if popover.isShown {
                    popover.performClose(nil)
                } else {
                    // Option-click always starts from the projects list
                    showMainContent(fromRoot: event.modifierFlags.contains(.option))
                }
            }
        }
    }

    /// Shows the main content, reusing the previous view (and its navigation stack)
    /// when "Open at last visited page" is on, unless `fromRoot` is requested.
    private func showMainContent(fromRoot: Bool) {
        guard let popover = popover, let button = statusItem?.button else { return }

        if fromRoot || !SettingsManager.shared.openAtLastPage || mainController == nil {
            mainController = NSHostingController(rootView: ContentView())
        }
        popover.contentViewController = mainController
        show(popover, from: button)
    }

    /// Anchors the popover to the status bar button and makes it key, so keyboard
    /// shortcuts work (a menu bar app isn't active until it activates itself).
    private func show(_ popover: NSPopover, from button: NSStatusBarButton) {
        let positioningRect = NSRect(x: 0, y: 0, width: button.bounds.width, height: button.bounds.height)
        popover.show(relativeTo: positioningRect, of: button, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc func openRoot() {
        showMainContent(fromRoot: true)
    }
    
    private func showContextMenu(for button: NSStatusBarButton) {
        let menu = NSMenu()

        if SettingsManager.shared.openAtLastPage {
            let rootItem = NSMenuItem(title: "Open Projects", action: #selector(openRoot), keyEquivalent: "")
            rootItem.target = self
            menu.addItem(rootItem)
        }

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }
    
    @objc func openSettings() {
        // Show the popover with settings view wrapped in ContentView for auth context
        if let button = statusItem?.button {
            if let popover = popover {
                // Create a special view that shows settings within the auth context
                // Settings runs with its own auth service (logout there isn't seen by the
                // kept main view), so the next left-click starts fresh
                mainController = nil
                let settingsContentView = SettingsContentView()
                popover.contentViewController = NSHostingController(rootView: settingsContentView)
                show(popover, from: button)
            }
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// Wrapper view to provide auth context for settings
struct SettingsContentView: View {
    @StateObject private var authService = AuthenticationService()

    var body: some View {
        NavigationStack {
            SettingsView()
        }
        .environmentObject(authService)
    }
}

