//
//  KeyboardShortcuts.swift
//  GitlabMenubar
//

import SwiftUI

extension View {
    /// Shortcut for an action without a visible control (an invisible button carries it).
    func shortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void) -> some View {
        background {
            Button("", action: action)
                .keyboardShortcut(key, modifiers: modifiers)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// ⌘[ and Esc go back on a pushed page. On the root page Esc is left alone, so it closes the popover.
    func backShortcuts() -> some View {
        modifier(BackShortcuts())
    }
}

private struct BackShortcuts: ViewModifier {
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        if isPresented {
            content
                .shortcut("[") { dismiss() }
                .shortcut(.escape, modifiers: []) { dismiss() }
        } else {
            content
        }
    }
}
