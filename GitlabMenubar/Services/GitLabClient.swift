//
//  GitLabClient.swift
//  GitlabMenubar
//
//  Created by Antigravity on 16/12/2025.
//

import Foundation

class GitLabClient {
    private let authService: AuthenticationService
    
    init(authService: AuthenticationService) {
        self.authService = authService
    }
    
    struct Project: Codable, Identifiable {
        let id: Int
        let name: String
        let pathWithNamespace: String
        let starCount: Int
        let webUrl: String
        
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case pathWithNamespace = "path_with_namespace"
            case starCount = "star_count"
            case webUrl = "web_url"
        }
    }

    struct User: Codable, Identifiable {
        let id: Int
        let username: String
        let name: String
        let avatarUrl: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case username
            case name
            case avatarUrl = "avatar_url"
        }
    }
    
    struct MergeRequest: Codable, Identifiable {
        let id: Int
        let iid: Int
        let title: String
        let state: String
        let webUrl: String
        let author: User
        let assignees: [User]?
        let reviewers: [User]?
        let detailedMergeStatus: String?
        let mergedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case iid
            case title
            case state
            case webUrl = "web_url"
            case author
            case assignees
            case reviewers
            case detailedMergeStatus = "detailed_merge_status"
            case mergedAt = "merged_at"
        }
    }
    
    struct GitLabErrorResponse: Codable {
        let error: String?
        let errorDescription: String?
        let message: String?
        
        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
            case message
        }
        
        var displayMessage: String {
            if let error = error {
                return error
            }
            if let errorDescription = errorDescription {
                return errorDescription
            }
            if let message = message {
                return message
            }
            return "Unknown error"
        }
    }
    
    enum ClientError: Error, LocalizedError {
        case invalidURL
        case missingToken
        case requestFailed(String?)
        case decodingError
        case unauthorized(String?)
        case expiredToken(String?)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .missingToken:
                return "Missing authentication token"
            case .requestFailed(let message):
                return message ?? "Request failed"
            case .decodingError:
                return "Failed to decode response"
            case .unauthorized(let message):
                return message ?? "Unauthorized"
            case .expiredToken(let message):
                return message ?? "Token has expired"
            }
        }
    }
    
    func fetchStarredProjects() async throws -> [Project] {
        guard let token = authService.loadToken() else {
            throw ClientError.missingToken
        }
        
        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        // Use membership=true to ensure we see projects we have access to
        guard let url = URL(string: "\(baseURLString)/api/v4/projects?starred=true&simple=true&membership=true&order_by=updated_at&sort=desc") else {
             throw ClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                throw ClientError.unauthorized(nil)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ClientError.requestFailed(nil)
            }
        }
        
        do {
            let projects = try JSONDecoder().decode([Project].self, from: data)
            return projects
        } catch {
            print("Decoding error: \(error)")
            throw ClientError.decodingError
        }
    }
    
    func searchProjects(query: String) async throws -> [Project] {
        guard let token = authService.loadToken() else {
            throw ClientError.missingToken
        }
        
        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ClientError.invalidURL
        }
        
        // Search projects with membership=true to see projects we have access to
        guard let url = URL(string: "\(baseURLString)/api/v4/projects?search=\(encodedQuery)&simple=true&membership=true&order_by=updated_at&sort=desc&per_page=50") else {
             throw ClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                throw ClientError.unauthorized(nil)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ClientError.requestFailed(nil)
            }
        }
        
        do {
            let projects = try JSONDecoder().decode([Project].self, from: data)
            return projects
        } catch {
            print("Decoding error: \(error)")
            throw ClientError.decodingError
        }
    }
    
    func validateToken() async throws -> Bool {
        guard let token = authService.loadToken() else { 
            throw ClientError.missingToken
        }
        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(baseURLString)/api/v4/user") else { 
            throw ClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                return true
            }
            
            // Parse error response
            if httpResponse.statusCode == 401 {
                let errorMessage = parseErrorResponse(from: data)
                
                // Check if it's an expired token
                if errorMessage.uppercased().contains("EXPIRED") {
                    throw ClientError.expiredToken(errorMessage)
                } else {
                    throw ClientError.unauthorized(errorMessage)
                }
            }
            
            // Other error codes
            let errorMessage = parseErrorResponse(from: data)
            throw ClientError.requestFailed(errorMessage)
        }
        
        throw ClientError.requestFailed(nil)
    }
    
    private func parseErrorResponse(from data: Data) -> String {
        if let errorResponse = try? JSONDecoder().decode(GitLabErrorResponse.self, from: data) {
            return errorResponse.displayMessage
        }
        
        // Fallback: try to parse as plain text
        if let errorString = String(data: data, encoding: .utf8), !errorString.isEmpty {
            return errorString
        }
        
        return "Unknown error"
    }
    
    struct Event: Codable {
        let projectId: Int?
        
        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
        }
    }
    
    func fetchRecentActivityProjectIds(after date: Date) async throws -> Set<Int> {
        guard let token = authService.loadToken() else { return [] }
        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let dateString = formatter.string(from: date)
        
        var activeProjectIds = Set<Int>()
        var page = 1
        var hasMorePages = true
        
        while hasMorePages {
            guard let url = URL(string: "\(baseURLString)/api/v4/events?after=\(dateString)&per_page=100&page=\(page)") else {
                break
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                break
            }
            
            do {
                let events = try JSONDecoder().decode([Event].self, from: data)
                if events.isEmpty {
                    hasMorePages = false
                } else {
                    let newIds = events.compactMap { $0.projectId }
                    activeProjectIds.formUnion(newIds)
                    page += 1
                }
            } catch {
                print("Decoding error events: \(error)")
                hasMorePages = false
            }
        }
        
        return activeProjectIds
    }
    
    struct Issue: Codable, Identifiable {
        let id: Int
        let iid: Int
        let title: String
        let description: String?
        let state: String
        let webUrl: String
        let labels: [String]
        let assignees: [User]?

        enum CodingKeys: String, CodingKey {
            case id
            case iid
            case title
            case description
            case state
            case webUrl = "web_url"
            case labels
            case assignees
        }
    }
    
    struct Label: Codable, Identifiable, Hashable {
        let id: Int
        let name: String
        let color: String
        let textColor: String
        
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case color
            case textColor = "text_color"
        }
    }
    
    func fetchProjectLabels(projectId: Int) async throws -> [Label] {
        guard let token = authService.loadToken() else {
            throw ClientError.missingToken
        }
        
        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        var allLabels: [Label] = []
        var page = 1
        var hasMorePages = true
        
        while hasMorePages {
            guard let url = URL(string: "\(baseURLString)/api/v4/projects/\(projectId)/labels?per_page=100&page=\(page)") else {
                 throw ClientError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    throw ClientError.unauthorized(nil)
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw ClientError.requestFailed(nil)
                }
            }
            
            do {
                let labels = try JSONDecoder().decode([Label].self, from: data)
                if labels.isEmpty {
                    hasMorePages = false
                } else {
                    allLabels.append(contentsOf: labels)
                    page += 1
                }
            } catch {
                print("Decoding error labels: \(error)")
                throw ClientError.decodingError
            }
        }
        
        return allLabels
    }
    
    func fetchProjectIssues(projectId: Int, labels: [String]? = nil) async throws -> [Issue] {
        guard let token = authService.loadToken() else {
            throw ClientError.missingToken
        }
        
        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        var urlString = "\(baseURLString)/api/v4/projects/\(projectId)/issues?state=opened&per_page=100"
        
        if let labels = labels, !labels.isEmpty {
            let labelsParam = labels.joined(separator: ",")
            if let encodedLabels = labelsParam.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString += "&labels=\(encodedLabels)"
            }
        }
        
        // Fetch opened issues
        guard let url = URL(string: urlString) else {
             throw ClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                throw ClientError.unauthorized(nil)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ClientError.requestFailed(nil)
            }
        }
        
        do {
            let issues = try JSONDecoder().decode([Issue].self, from: data)
            return issues
        } catch {
            print("Decoding error: \(error)")
            throw ClientError.decodingError
        }
    }

    func fetchCurrentUser() async throws -> User {
        guard let token = authService.loadToken() else {
            throw ClientError.missingToken
        }
        
        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(baseURLString)/api/v4/user") else {
             throw ClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                throw ClientError.unauthorized(nil)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ClientError.requestFailed(nil)
            }
        }
        
        do {
            let user = try JSONDecoder().decode(User.self, from: data)
            return user
        } catch {
            print("Decoding user error: \(error)")
            throw ClientError.decodingError
        }
    }
    
    func fetchProjectMergeRequests(projectId: Int, scope: String? = nil, reviewerId: Int? = nil, state: String = "opened") async throws -> [MergeRequest] {
        guard let token = authService.loadToken() else {
            throw ClientError.missingToken
        }

        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        var urlString = "\(baseURLString)/api/v4/projects/\(projectId)/merge_requests?state=\(state)&per_page=100"

        if let scope = scope {
            urlString += "&scope=\(scope)"
        }

        if let reviewerId = reviewerId {
            urlString += "&reviewer_id=\(reviewerId)"
        }

        guard let url = URL(string: urlString) else {
             throw ClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                let errorMessage = parseErrorResponse(from: data)
                throw ClientError.unauthorized(errorMessage)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = parseErrorResponse(from: data)
                throw ClientError.requestFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }
        }

        do {
            let mrs = try JSONDecoder().decode([MergeRequest].self, from: data)
            return mrs
        } catch {
            print("Decoding MRs error: \(error)")
            throw ClientError.decodingError
        }
    }
    
    struct Pipeline: Codable, Identifiable {
        let id: Int
        let iid: Int
        let status: String
        let ref: String
        let webUrl: String
        let createdAt: String
        let updatedAt: String
        
        enum CodingKeys: String, CodingKey {
            case id
            case iid
            case status
            case ref
            case webUrl = "web_url"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }
    
    func fetchProjectPipelines(projectId: Int, status: String? = nil) async throws -> [Pipeline] {
        guard let token = authService.loadToken() else {
            throw ClientError.missingToken
        }
        
        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        var urlString = "\(baseURLString)/api/v4/projects/\(projectId)/pipelines?per_page=20"
        
        if let status = status {
            urlString += "&status=\(status)"
        }
        
        guard let url = URL(string: urlString) else {
             throw ClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                throw ClientError.unauthorized(nil)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ClientError.requestFailed(nil)
            }
        }
        
        do {
            let pipelines = try JSONDecoder().decode([Pipeline].self, from: data)
            return pipelines
        } catch {
            print("Decoding Pipelines error: \(error)")
            throw ClientError.decodingError
        }
    }
}
