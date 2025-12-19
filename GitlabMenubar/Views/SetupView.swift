//
//  SetupView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 16/12/2025.
//

import SwiftUI

struct SetupView: View {
    @EnvironmentObject var authService: AuthenticationService
    
    @State private var token: String = ""
    @State private var verifyError: String?
    @State private var isVerifying: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to GitLab")
                .font(.headline)
            
            VStack(alignment: .leading) {
                Text("GitLab Instance URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://gitlab.com", text: $authService.gitlabURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading) {
                Text("Personal Access Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Token", text: $token)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Required Scope:")
                    .font(.caption)
                    .bold()
                Text("Please generate a token with the `api` scope.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let verifyError {
                Text(verifyError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            
            Button {
                verifyToken()
            } label: {
                HStack {
                    if isVerifying {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Connect")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.isEmpty || isVerifying)
        }
        .padding()
        .frame(width: 300)
    }
    
    private func verifyToken() {
        guard !token.isEmpty else { return }
        isVerifying = true
        verifyError = nil
        
        let client = GitLabClient(authService: authService)
        
        // Save token temporarily for validation
        let saved = authService.saveToken(token)
        if !saved {
            verifyError = "Failed to save token"
            isVerifying = false
            return
        }
        
        Task {
            do {
                let success = try await client.validateToken()
                await MainActor.run {
                    isVerifying = false
                    if !success {
                        verifyError = "Invalid token or URL"
                        authService.logout()
                    }
                }
            } catch let error as GitLabClient.ClientError {
                await MainActor.run {
                    isVerifying = false
                    // Display the specific error message from GitLab
                    verifyError = error.localizedDescription
                    authService.logout()
                }
            } catch {
                await MainActor.run {
                    isVerifying = false
                    verifyError = error.localizedDescription
                    authService.logout()
                }
            }
        }
    }
}

#Preview {
    SetupView()
        .environmentObject(AuthenticationService())
}
