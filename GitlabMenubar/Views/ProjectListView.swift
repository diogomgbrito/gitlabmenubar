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
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [GitLabClient.Project] = []
    
    enum FilterMode: String, CaseIterable, Identifiable {
        case active = "Active"
        case all = "All Starred"
        var id: String { self.rawValue }
    }
    
    @State private var filterMode: FilterMode = .active
    
    var body: some View {
        VStack(spacing: 12) {
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
                .disabled(!searchText.isEmpty)
                
                Button {
                    Task {
                        if searchText.isEmpty {
                            await loadProjects()
                        } else {
                            await performSearch()
                        }
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
            .padding(.horizontal)
            .padding(.top, 20)
            
            HStack(spacing: 8) {
                TextField("Search projects...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task {
                            await performSearch()
                        }
                    }
                
                Button {
                    Task {
                        await performSearch()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(searchText.isEmpty || isSearching)
                .buttonStyle(.bordered)
                
                if !searchText.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            
            if isLoading && allProjects.isEmpty && searchResults.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text("Error loading projects")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadProjects() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if projects.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Text(searchText.isEmpty ? "No projects found" : "No results found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "Try refreshing or check your GitLab instance" : "Try a different search term")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(projects) { project in
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
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
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
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
        clearSearch()
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
    
    private func performSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            clearSearch()
            return
        }
        
        isSearching = true
        errorMessage = nil
        let client = GitLabClient(authService: authService)
        
        do {
            let results = try await client.searchProjects(query: searchText)
            await MainActor.run {
                self.searchResults = results
                self.projects = results
                self.isSearching = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isSearching = false
            }
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchResults = []
        applyFilter()
    }
}

#Preview {
    ProjectListView()
        .environmentObject(AuthenticationService())
}
