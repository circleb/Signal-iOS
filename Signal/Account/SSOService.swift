import AppAuth
import SignalServiceKit
import Foundation

protocol SSOServiceProtocol {
    func authenticate() -> Promise<SSOUserInfo>
    func getUserInfo(accessToken: String) -> Promise<SSOUserInfo>
    func refreshToken() -> Promise<SSOUserInfo>
    func signOut() -> Promise<Void>
}

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

class SSOService: SSOServiceProtocol {
    private var authState: OIDAuthState?
    private let userInfoStore: SSOUserInfoStore

    init(userInfoStore: SSOUserInfoStore) {
        self.userInfoStore = userInfoStore
    }

    func authenticate() -> Promise<SSOUserInfo> {
        let (promise, future) = Promise<SSOUserInfo>.pending()
        
        guard let authorizationEndpoint = URL(string: SSOConfig.authorizationEndpoint),
              let tokenEndpoint = URL(string: SSOConfig.tokenEndpoint),
              let redirectURI = URL(string: SSOConfig.redirectURI) else {
            future.reject(SSOError.configurationError)
            return promise
        }

        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint
        )

        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: SSOConfig.clientId,
            clientSecret: SSOConfig.clientSecret,
            scopes: SSOConfig.scopes,
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        // Get the current view controller for presentation
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let presentingViewController = windowScene.windows.first?.rootViewController else {
            future.reject(SSOError.configurationError)
            return promise
        }

        OIDAuthState.authState(byPresenting: request, presenting: presentingViewController) { authState, error in
            if let error = error {
                // Check if it's a user cancellation error
                let nsError = error as NSError
                if nsError.domain == "org.openid.appauth.general" && nsError.code == -3 {
                    future.reject(SSOError.userCancelled)
                } else {
                    future.reject(SSOError.networkError(error))
                }
                return
            }

            guard let authState = authState,
                  let accessToken = authState.lastTokenResponse?.accessToken else {
                future.reject(SSOError.invalidToken)
                return
            }

            self.authState = authState

            // Get user info
            self.getUserInfo(accessToken: accessToken)
                .done { userInfo in
                    self.userInfoStore.storeUserInfo(userInfo)
                    future.resolve(userInfo)
                }
                .catch { error in
                    future.reject(error)
                }
        }
        
        return promise
    }

    func getUserInfo(accessToken: String) -> Promise<SSOUserInfo> {
        let (promise, future) = Promise<SSOUserInfo>.pending()
        
        guard let userInfoURL = URL(string: SSOConfig.userInfoEndpoint) else {
            future.reject(SSOError.configurationError)
            return promise
        }

        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                future.reject(SSOError.networkError(error))
                return
            }

            guard let data = data else {
                future.reject(SSOError.invalidUserInfo)
                return
            }

            do {
                let keycloakUserInfo = try JSONDecoder().decode(KeycloakUserInfo.self, from: data)
                let userInfo = SSOUserInfo(from: keycloakUserInfo, accessToken: accessToken, refreshToken: nil)
                
                // Validate required roles
                if !self.hasRequiredRoles(userInfo.roles) {
                    future.reject(SSOError.roleAccessDenied)
                    return
                }

                future.resolve(userInfo)
            } catch {
                future.reject(SSOError.invalidUserInfo)
            }
        }.resume()
        
        return promise
    }

    func refreshToken() -> Promise<SSOUserInfo> {
        let (promise, future) = Promise<SSOUserInfo>.pending()
        
        guard let authState = authState else {
            future.reject(SSOError.invalidToken)
            return promise
        }

        authState.performAction { accessToken, idToken, error in
            if let error = error {
                future.reject(SSOError.networkError(error))
                return
            }

            guard let accessToken = accessToken else {
                future.reject(SSOError.invalidToken)
                return
            }

            self.getUserInfo(accessToken: accessToken)
                .done { userInfo in
                    self.userInfoStore.storeUserInfo(userInfo)
                    future.resolve(userInfo)
                }
                .catch { error in
                    future.reject(error)
                }
        }
        
        return promise
    }

    func signOut() -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()
        
        // For now, just clear local state
        // TODO: Implement proper end session request with OIDExternalUserAgent
        self.authState = nil
        self.userInfoStore.clearUserInfo()
        future.resolve(())
        
        return promise
    }

    private func hasRequiredRoles(_ userRoles: [String]) -> Bool {
        let hasAnyRequiredRole = SSOConfig.requiredRoles.contains { requiredRole in
            userRoles.contains(requiredRole)
        }
        return hasAnyRequiredRole
    }
} 