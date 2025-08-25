//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI
import SignalUI
import SignalServiceKit

struct AccessRequestFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    let blockedURL: String
    let userInfo: SSOUserInfo
    
    var body: some View {
        NavigationView {
            SignalList {
                SignalSection {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Blocked Site")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(blockedURL)
                            .font(.body)
                            .foregroundColor(.secondary)

                        Text("Please provide a reason why you believe this website should be accessible.")
                            .font(.body)
                        
                        TextEditor(text: $reason)
                            .frame(minHeight: 120)
                            .padding(12)
                            .background(Color.Signal.secondaryBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.Signal.opaqueSeparator, lineWidth: 1)
                            )
                        Text("Your name and email address will be used to contact you if we need further information.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text(userInfo.name ?? "Unknown User")
                            .foregroundColor(.secondary)
                        + Text(" • ")
                            .foregroundColor(.secondary)
                        + Text(userInfo.email ?? "Unknown Email")
                            .foregroundColor(.secondary)
                        
                    }
                    .padding(.vertical, 16)
                }
                
                if showError {
                    SignalSection {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .foregroundColor(.red)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                if showSuccess {
                    SignalSection {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Access request submitted successfully!")
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Request Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Submit") {
                            submitRequest()
                        }
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
    
    private func submitRequest() {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSubmitting = true
        showError = false
        showSuccess = false
        
        let requestData: [String: Any] = [
            "reason": reason.trimmingCharacters(in: .whitespacesAndNewlines),
            "blocked_url": blockedURL,
            "user_name": userInfo.name ?? "Unknown",
            "user_email": userInfo.email ?? "Unknown",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let url = URL(string: "https://automation.heritageserver.com/webhook/ad687809-b4a5-4bb4-b11e-44f418561584") else {
            showError(message: "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
        } catch {
            showError(message: "Failed to prepare request data")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSubmitting = false
                
                if let error = error {
                    showError(message: "Network error: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        // Success
                        showSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    } else {
                        showError(message: "Server error: \(httpResponse.statusCode)")
                    }
                } else {
                    showError(message: "Invalid response from server")
                }
            }
        }.resume()
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
        showSuccess = false
        isSubmitting = false
    }
}

#Preview {
    AccessRequestFormView(
        blockedURL: "https://example.com",
        userInfo: SSOUserInfo(
            phoneNumber: "+1234567890",
            email: "user@example.com",
            name: "John Doe",
            sub: "123",
            accessToken: "token",
            refreshToken: nil,
            roles: [],
            groups: [],
            realmAccess: nil,
            resourceAccess: nil
        )
    )
}
