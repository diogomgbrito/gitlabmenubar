//
//  ProjectListView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 16/12/2025.
//

import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject var authService: AuthenticationService
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var allProjects: [GitLabClient.Project] = []
    @State private var projects: [GitLabClient.Project] = []
    @State private var activeProjectIds: Set<Int> = []

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [GitLabClient.Project] = []
    @State private var showSearch = false

    enum FilterMode: String, CaseIterable {
        case active = "Active"
        case all = "All"
    }

    @State private var filterMode: FilterMode = .active

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Text("Projects")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()

                NavigationLink {
                    ReviewsView()
                } label: {
                    Image(systemName: "arrow.triangle.pull")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("MRs needing your review")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showSearch.toggle() }
                    if !showSearch { clearSearch() }
                } label: {
                    Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)

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
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .disabled(isLoading || isSearching)

                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Filter tabs or search field
            if showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search projects...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit {
                            Task { await performSearch() }
                        }
                    if !searchText.isEmpty {
                        Button {
                            clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            } else {
                HStack(spacing: 18) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Button(mode.rawValue) {
                            filterMode = mode
                        }
                        .font(.system(size: 12, weight: filterMode == mode ? .semibold : .regular))
                        .foregroundStyle(filterMode == mode ? .primary : .secondary)
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if filterMode == mode {
                                Rectangle()
                                    .frame(height: 1.5)
                                    .foregroundStyle(Color.accentColor)
                                    .offset(y: 6)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            Divider()

            // Content
            if isLoading && allProjects.isEmpty && searchResults.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text("Error loading projects")
                        .font(.system(size: 13, weight: .medium))
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
                VStack(spacing: 8) {
                    Text(searchText.isEmpty ? "No projects found" : "No results found")
                        .font(.system(size: 13, weight: .medium))
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(project.pathWithNamespace)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .onAppear {
            Task { await loadProjects() }
        }
        .onChange(of: filterMode) { _, _ in applyFilter() }
        .onChange(of: settingsManager.activeTimeMonths) { _, _ in
            Task { await loadProjects() }
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
