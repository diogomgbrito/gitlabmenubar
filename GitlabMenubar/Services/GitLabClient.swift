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
    
    enum ClientError: Error {
        case invalidURL
        case missingToken
        case requestFailed
        case decodingError
        case unauthorized
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
                throw ClientError.unauthorized
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ClientError.requestFailed
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
        guard let token = authService.loadToken() else { return false }
        let baseURLString = authService.gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(baseURLString)/api/v4/user") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            return httpResponse.statusCode == 200
        }
        return false
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
}
