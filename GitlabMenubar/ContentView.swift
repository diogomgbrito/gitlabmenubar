//
//  ContentView.swift
//  GitlabMenubar
//
//  Created by Diogo Brito on 16/12/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authService = AuthenticationService()

    var body: some View {
        Group {
            if authService.isAuthenticated {
                NavigationStack {
                    ProjectListView()
                }
            } else {
                SetupView()
            }
        }
        .background(.ultraThinMaterial)
        .environmentObject(authService)
    }
}

#Preview {
    ContentView()
}
