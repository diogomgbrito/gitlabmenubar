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
            if authService.isLocked {
                VStack(spacing: 20) {
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                    Text("GitLab Access Locked")
                        .font(.headline)
                    Button("Unlock with Touch ID") {
                        authService.unlock()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(width: 300, height: 200)
                .onAppear {
                    // Try to unlock immediately on appear
                    authService.unlock()
                }
            } else if authService.isAuthenticated {
                NavigationStack {
                    ProjectListView()
                }
            } else {
                SetupView()
            }
        }
        .environmentObject(authService)
    }
}

#Preview {
    ContentView()
}
