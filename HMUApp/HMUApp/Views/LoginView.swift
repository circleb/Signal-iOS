import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authState: AuthStateManager
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showRegisterSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Hero
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.hcpBlue)
                    .padding(.bottom, 32)

                Text("HMU Chat")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 8)

                Text("Sign in with your Heritage account to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.3)
                            .padding()
                    } else {
                        Button(action: handleSignIn) {
                            Label("Sign In", systemImage: "person.badge.key.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.hcpBlue)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .padding(.horizontal)

                        Button("Register") { showRegisterSheet = true }
                            .font(.headline)
                            .foregroundColor(.hcpBlue)
                            .padding(.vertical, 8)
                    }

                    Text("[Terms of Service & Privacy Policy](https://my.homesteadheritage.org/terms)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .tint(.secondary)
                        .padding(.bottom, 8)
                }
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showRegisterSheet) {
            WebSheetView(
                url: URL(string: "https://my.homesteadheritage.org/register")!,
                title: "Register"
            )
        }
    }

    private func handleSignIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let userInfo = try await authState.ssoService.authenticate()
                await MainActor.run {
                    authState.signIn(userInfo)
                    isLoading = false
                }
            } catch let error as SSOError {
                await MainActor.run {
                    isLoading = false
                    switch error {
                    case .userCancelled: errorMessage = nil
                    case .networkError: errorMessage = "Network error. Check your connection and try again."
                    case .invalidToken: errorMessage = "Authentication failed. Please try again."
                    case .roleAccessDenied: errorMessage = "Access denied. Your account doesn't have the required role."
                    default: errorMessage = "Sign in failed. Please try again."
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
