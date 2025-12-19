//
//  ProjectListView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 16/12/2025.
//

import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var settingsManager = SettingsManager()
    @State private var allProjects: [GitLabClient.Project] = []
    @State private var projects: [GitLabClient.Project] = []
    @State private var activeProjectIds: Set<Int> = []
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    enum FilterMode: String, CaseIterable, Identifiable {
        case active = "Active"
        case all = "All Starred"
        var id: String { self.rawValue }
    }
    
    @State private var filterMode: FilterMode = .active
    
    var body: some View {
        VStack {
            HStack {
                Text("Projects")
                    .font(.headline)
                Spacer()
                
                Picker("Filter", selection: $filterMode) {
                    ForEach(FilterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                
                Button {
                    Task {
                        await loadProjects()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .buttonStyle(.bordered)
                
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
            .padding(.horizontal)
            
            if isLoading && allProjects.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack {
                    Text("Error loading projects")
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await loadProjects() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(projects) { project in
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(project.name)
                                    .font(.body)
                                Text(project.pathWithNamespace)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                            Text("\(project.starCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(width: 350, height: 450)
        .onAppear {
            Task {
                await loadProjects()
            }
        }
        .onChange(of: filterMode) { _, _ in
            applyFilter()
        }
        .onChange(of: settingsManager.activeTimeMonths) { _, _ in
            Task {
                await loadProjects()
            }
        }
        .environmentObject(settingsManager)
    }
    
    private func loadProjects() async {
        isLoading = true
        errorMessage = nil
        let client = GitLabClient(authService: authService)
        
        do {
            async let starredProjectsTask = client.fetchStarredProjects()
            // Use dynamic active time from settings
            let date = Calendar.current.date(byAdding: .month, value: -settingsManager.activeTimeMonths, to: Date()) ?? Date()
            async let userEventsTask = client.fetchRecentActivityProjectIds(after: date)
            
            let (fetchedProjects, fetchedIds) = try await (starredProjectsTask, userEventsTask)
            
            await MainActor.run {
                self.allProjects = fetchedProjects
                self.activeProjectIds = fetchedIds
                self.isLoading = false
                self.applyFilter()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func applyFilter() {
        switch filterMode {
        case .all:
            self.projects = self.allProjects
        case .active:
            self.projects = self.allProjects.filter { activeProjectIds.contains($0.id) }
        }
    }
}

#Preview {
    ProjectListView()
        .environmentObject(AuthenticationService())
}
