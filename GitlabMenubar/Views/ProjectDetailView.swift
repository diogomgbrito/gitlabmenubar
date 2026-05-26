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

    enum Tab {
        case tasks, mrs, pipelines
    }

    @State private var selectedTab: Tab = .tasks

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon tab buttons
            HStack(spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)

                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                HStack(spacing: 16) {
                    tabButton(.tasks, icon: "checklist")
                    tabButton(.mrs, icon: "arrow.triangle.pull")
                    tabButton(.pipelines, icon: "hammer")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Tab content
            switch selectedTab {
            case .tasks:
                ProjectTasksView(project: project)
            case .mrs:
                ProjectMRsView(project: project)
            case .pipelines:
                ProjectPipelinesView(project: project)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func tabButton(_ tab: Tab, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProjectDetailView(project: GitLabClient.Project(id: 1, name: "Test Project", pathWithNamespace: "group/test-project", starCount: 10, webUrl: "https://gitlab.com/group/test-project"))
        .environmentObject(AuthenticationService())
}
