//
//  ProjectDetailView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 16/12/2025.
//

import SwiftUI

struct ProjectDetailView: View {
    let project: GitLabClient.Project
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    // Default to tasks tab
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(project.name)
                    .font(.headline)
                
                Spacer()
            }
            .padding(.top, 20)
            .padding(.horizontal)
            .padding(.bottom, 10)
            .background(.regularMaterial)
            
            Divider()
            
            TabView(selection: $selectedTab) {
                ProjectTasksView(project: project)
                    .tabItem {
                        Label("Tasks", systemImage: "checklist")
                    }
                    .tag(0)
                
                ProjectMRsView(project: project)
                    .tabItem {
                        Label("MRs", systemImage: "arrow.triangle.pull")
                    }
                    .tag(1)
                
                ProjectPipelinesView(project: project)
                    .tabItem {
                        Label("Pipelines", systemImage: "hammer")
                    }
                    .tag(2)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    ProjectDetailView(project: GitLabClient.Project(id: 1, name: "Test Project", pathWithNamespace: "group/test-project", starCount: 10, webUrl: "https://gitlab.com/group/test-project"))
        .environmentObject(AuthenticationService())
}
