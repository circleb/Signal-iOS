import AppAuth
import UIKit

public enum SSOError: Error {
    case networkError(Error)
    case invalidToken
    case userCancelled
    case serverError(String)
    case invalidUserInfo
    case missingPhoneNumber
    case roleAccessDenied
    case configurationError
}

// Singleton manager so the OAuth callback can reach the active flow
final class SSOServiceManager {
    static let shared = SSOServiceManager()
    private var currentService: SSOService?
    private init() {}

    func register(_ service: SSOService) { currentService = service }
    func unregister() { currentService = nil }

    func handleOAuthCallback(url: URL) -> Bool {
        currentService?.handleOAuthCallback(url: url) ?? false
    }
}

final class SSOService {
    private var authState: OIDAuthState?
    private var currentFlow: OIDExternalUserAgentSession?
    let store: SSOUserInfoStore

    init(store: SSOUserInfoStore = .shared) {
        self.store = store
    }

    // MARK: - Authenticate

    func authenticate() async throws -> SSOUserInfo {
        guard let authEndpoint = URL(string: SSOConfig.authorizationEndpoint),
              let tokenEndpoint = URL(string: SSOConfig.tokenEndpoint),
              let redirectURI = URL(string: SSOConfig.redirectURI) else {
            throw SSOError.configurationError
        }

        let config = OIDServiceConfiguration(
            authorizationEndpoint: authEndpoint,
            tokenEndpoint: tokenEndpoint
        )
        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: SSOConfig.clientId,
            clientSecret: SSOConfig.clientSecret.isEmpty ? nil : SSOConfig.clientSecret,
            scopes: SSOConfig.scopes,
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else {
            throw SSOError.configurationError
        }

        SSOServiceManager.shared.register(self)

        return try await withCheckedThrowingContinuation { continuation in
            self.currentFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: root
            ) { [weak self] authState, error in
                SSOServiceManager.shared.unregister()

                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == "org.openid.appauth.general" && nsError.code == -3 {
                        continuation.resume(throwing: SSOError.userCancelled)
                    } else {
                        continuation.resume(throwing: SSOError.networkError(error))
                    }
                    return
                }

                guard let authState,
                      let accessToken = authState.lastTokenResponse?.accessToken else {
                    continuation.resume(throwing: SSOError.invalidToken)
                    return
                }

                self?.authState = authState

                Task {
                    do {
                        let userInfo = try await self?.fetchUserInfo(accessToken: accessToken)
                            ?? { throw SSOError.invalidUserInfo }()
                        self?.store.storeUserInfo(userInfo)
                        continuation.resume(returning: userInfo)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - User Info

    func fetchUserInfo(accessToken: String) async throws -> SSOUserInfo {
        guard let url = URL(string: SSOConfig.userInfoEndpoint) else {
            throw SSOError.configurationError
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: req)
        let keycloak = try JSONDecoder().decode(KeycloakUserInfo.self, from: data)
        return SSOUserInfo(from: keycloak, accessToken: accessToken, refreshToken: nil)
    }

    // MARK: - Refresh

    func refreshToken() async throws -> SSOUserInfo {
        guard let authState else { throw SSOError.invalidToken }

        return try await withCheckedThrowingContinuation { continuation in
            authState.performAction { [weak self] accessToken, _, error in
                if let error { continuation.resume(throwing: SSOError.networkError(error)); return }
                guard let accessToken else { continuation.resume(throwing: SSOError.invalidToken); return }
                Task {
                    do {
                        let info = try await self?.fetchUserInfo(accessToken: accessToken)
                            ?? { throw SSOError.invalidUserInfo }()
                        self?.store.storeUserInfo(info)
                        continuation.resume(returning: info)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        authState = nil
        store.clearUserInfo()
    }

    // MARK: - OAuth Callback

    func handleOAuthCallback(url: URL) -> Bool {
        currentFlow?.resumeExternalUserAgentFlow(with: url) ?? false
    }
}
