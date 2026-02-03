//
//  SettingsView.swift
//  GitlabMenubar
//
//  Created by Antigravity on 18/12/2025.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var settingsManager = SettingsManager()

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                
                Text("General Settings")
                    .font(.headline)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Projects Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Projects")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        
                        HStack {
                            Text("Active projects from last")
                                .font(.body)
                            
                            Picker(selection: $settingsManager.activeTimeMonths) {
                                ForEach(1...6, id: \.self) { months in
                                    Text("\(months) month\(months > 1 ? "s" : "")").tag(months)
                                }
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.menu)
                            .frame(width: 100)
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Account Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        
                        Button {
                            authService.logout()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundStyle(.orange)
                                Text("Logout")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Application Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Application")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        
                        Button {
                            NSApplication.shared.terminate(nil)
                        } label: {
                            HStack {
                                Image(systemName: "power")
                                    .foregroundStyle(.red)
                                Text("Quit App")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            
            Spacer()
        }
        .frame(width: 350, height: 450)
        .environmentObject(settingsManager)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationService())
}

