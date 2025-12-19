//
//  AppDelegate.swift
//  GitlabMenubar
//
//  Created by Diogo Brito on 16/12/2025.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status item in the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "GitLab")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Create the popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 350, height: 450)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: ContentView())
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
                    // Reset to main content view
                    popover.contentViewController = NSHostingController(rootView: ContentView())
                    // Show popover anchored to the status bar button
                    let positioningRect = NSRect(x: 0, y: 0, width: sender.bounds.width, height: sender.bounds.height)
                    popover.show(relativeTo: positioningRect, of: sender, preferredEdge: .minY)
                }
            }
        }
    }
    
    private func showContextMenu(for button: NSStatusBarButton) {
        let menu = NSMenu()
        
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
                let settingsContentView = SettingsContentView()
                popover.contentViewController = NSHostingController(rootView: settingsContentView)
                // Show popover anchored to the status bar button
                let positioningRect = NSRect(x: 0, y: 0, width: button.bounds.width, height: button.bounds.height)
                popover.show(relativeTo: positioningRect, of: button, preferredEdge: .minY)
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

