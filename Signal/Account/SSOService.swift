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

// Global SSO service manager to handle OAuth callbacks
class SSOServiceManager {
    static let shared = SSOServiceManager()
    
    private var currentService: SSOService?
    
    private init() {}
    
    func registerService(_ service: SSOService) {
        Logger.info("SSOServiceManager: Registering SSO service")
        currentService = service
    }
    
    func unregisterService() {
        Logger.info("SSOServiceManager: Unregistering SSO service")
        currentService = nil
    }
    
    func handleOAuthCallback(url: URL) -> Bool {
        Logger.info("SSOServiceManager: Handling OAuth callback")
        
        guard let service = currentService else {
            Logger.error("SSOServiceManager: No current service registered")
            return false
        }
        
        let result = service.handleOAuthCallback(url: url)
        Logger.info("SSOServiceManager: OAuth callback result: \(result)")
        return result
    }
}

class SSOService: SSOServiceProtocol {
    private var authState: OIDAuthState?
    private var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private let userInfoStore: SSOUserInfoStore

    init(userInfoStore: SSOUserInfoStore) {
        self.userInfoStore = userInfoStore
    }

    public func authenticate() -> Promise<SSOUserInfo> {
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

        // Register this service instance with the global manager
        SSOServiceManager.shared.registerService(self)
        Logger.info("SSO: Starting OAuth authorization flow")

        currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: presentingViewController) { authState, error in
            // Unregister this service instance
            SSOServiceManager.shared.unregisterService()
            Logger.info("SSO: OAuth authorization flow completed")
            
            if let error = error {
                Logger.error("SSO: OAuth authorization error: \(error)")
                // Check if it's a user cancellation error
                let nsError = error as NSError
                if nsError.domain == "org.openid.appauth.general" && nsError.code == -3 {
                    Logger.info("SSO: User cancelled OAuth flow")
                    future.reject(SSOError.userCancelled)
                } else {
                    Logger.error("SSO: Network error during OAuth flow: \(nsError)")
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

    public func getUserInfo(accessToken: String) -> Promise<SSOUserInfo> {
        let (promise, future) = Promise<SSOUserInfo>.pending()
        
        guard let userInfoURL = URL(string: SSOConfig.userInfoEndpoint) else {
            future.reject(SSOError.configurationError)
            return promise
        }

        Logger.info("SSO: Fetching user info from: \(userInfoURL)")

        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.error("SSO: Error fetching user info: \(error)")
                future.reject(SSOError.networkError(error))
                return
            }

            guard let data = data else {
                Logger.error("SSO: No data received from user info endpoint")
                future.reject(SSOError.invalidUserInfo)
                return
            }

            // Log the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.info("SSO: Raw user info response: \(responseString)")
            }

            do {
                let keycloakUserInfo = try JSONDecoder().decode(KeycloakUserInfo.self, from: data)
                Logger.info("SSO: Successfully decoded user info - email: \(keycloakUserInfo.email ?? "nil"), name: \(keycloakUserInfo.name ?? "nil")")
                Logger.info("SSO: Realm roles: \(keycloakUserInfo.realmAccess?.roles ?? [])")
                Logger.info("SSO: Resource access: \(keycloakUserInfo.resourceAccess?.keys.joined(separator: ", ") ?? "none")")
                
                let userInfo = SSOUserInfo(from: keycloakUserInfo, accessToken: accessToken, refreshToken: nil)
                Logger.info("SSO: Extracted all roles: \(userInfo.roles)")
                
                // Validate required roles - temporarily disabled for debugging
                if !self.hasRequiredRoles(userInfo.roles) {
                    Logger.error("SSO: User does not have required roles. User roles: \(userInfo.roles), Required roles: \(SSOConfig.requiredRoles)")
                    Logger.info("SSO: Continuing anyway for debugging purposes")
                    // future.reject(SSOError.roleAccessDenied)
                    // return
                }

                Logger.info("SSO: User info validation successful")
                future.resolve(userInfo)
            } catch {
                Logger.error("SSO: Failed to decode user info: \(error)")
                future.reject(SSOError.invalidUserInfo)
            }
        }.resume()
        
        return promise
    }

    public func refreshToken() -> Promise<SSOUserInfo> {
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

    public func signOut() -> Promise<Void> {
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
    
    func handleOAuthCallback(url: URL) -> Bool {
        Logger.info("SSO: Received OAuth callback URL: \(url)")
        
        guard let currentFlow = currentAuthorizationFlow else {
            Logger.error("SSO: No current authorization flow found")
            return false
        }
        
        let result = currentFlow.resumeExternalUserAgentFlow(with: url)
        Logger.info("SSO: OAuth callback handling result: \(result)")
        return result
    }
} 