# SSO Integration Implementation Guide for Signal App

## Overview

Integrate Single Sign-On (SSO) with Keycloak into the Signal app's registration flow. Users will first see the existing RegistrationSplashViewController, which will be modified to show an SSO login button. After successful SSO authentication, users will see a welcome message with their username and then the original options for setting up a Signal account or transferring from another device. The phone number field will be automatically populated during onboarding using data from the SSO provider.

## SSO Configuration

- **SSO Provider**: Keycloak
- **Host**: `auth.homesteadheritage.org`
- **Realm**: `heritage`
- **Client ID**: `signal_homesteadheritage_org`
- **Redirect URI**: `heritagesignal://oauth/callback`
- **User Info Endpoint**: `GET /realms/heritage/protocol/openid-connect/userinfo`

## Implementation Steps

### Step 1: Create SSO Infrastructure

#### 1.1 Create SSO Configuration

**File**: `SignalServiceKit/Account/SSOConfig.swift`

```swift
import AppAuth

struct SSOConfig {
    static let baseURL = "https://auth.homesteadheritage.org"
    static let realm = "heritage"
    static let clientId = "signal_homesteadheritage_org"
    static let clientSecret = "" // Configure if required by Keycloak

    // AppAuth configuration
    static let authorizationEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/auth"
    static let tokenEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/token"
    static let userInfoEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/userinfo"
    static let endSessionEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/logout"

    // OAuth2 scopes
    static let scopes = ["openid", "profile", "email", "phone", "roles", "groups"]

    // Redirect URI for iOS app
    static let redirectURI = "heritagesignal://callback"
}
```

#### 1.2 Create SSO Service

**File**: `SignalServiceKit/Account/SSOService.swift`

```swift
import AppAuth

protocol SSOServiceProtocol {
    func authenticate() -> Promise<SSOUserInfo>
    func getUserInfo(accessToken: String) -> Promise<SSOUserInfo>
    func refreshToken() -> Promise<SSOUserInfo>
    func signOut() -> Promise<Void>
}

struct SSOUserInfo {
    let phoneNumber: String?
    let email: String?
    let name: String?
    let sub: String
    let accessToken: String
    let refreshToken: String?
    let roles: [String]
    let groups: [String]
    let realmAccess: [String: [String]]? // Keycloak realm access roles
    let resourceAccess: [String: [String]]? // Keycloak resource access roles
}

class SSOService: SSOServiceProtocol {
    private var authState: OIDAuthState?

    func authenticate() -> Promise<SSOUserInfo> {
        // Use AppAuth's OIDAuthorizationService for OAuth2 flow
        // Configure with Keycloak endpoints and client credentials
    }

    func getUserInfo(accessToken: String) -> Promise<SSOUserInfo> {
        // Make HTTP request to Keycloak userinfo endpoint
    }

    func refreshToken() -> Promise<SSOUserInfo> {
        // Use AppAuth's built-in token refresh mechanism
    }

    func signOut() -> Promise<Void> {
        // Clear auth state and tokens
    }
}
```

#### 1.3 Create SSO User Info Store

**File**: `SignalServiceKit/Account/SSOUserInfoStore.swift`

```swift
protocol SSOUserInfoStore {
    func storeUserInfo(_ userInfo: SSOUserInfo)
    func getUserInfo() -> SSOUserInfo?
    func clearUserInfo()
    func getUserRoles() -> [String]
    func getUserGroups() -> [String]
    func hasRole(_ role: String) -> Bool
    func hasGroup(_ group: String) -> Bool
    func hasAnyRole(_ roles: [String]) -> Bool
    func hasAnyGroup(_ groups: [String]) -> Bool
}
```

#### 1.4 Create Role Manager

**File**: `SignalServiceKit/Account/SSORoleManager.swift`

```swift
protocol SSORoleManagerProtocol {
    func getUserRoles() -> [String]
    func getUserGroups() -> [String]
    func hasRole(_ role: String) -> Bool
    func hasGroup(_ group: String) -> Bool
    func hasAnyRole(_ roles: [String]) -> Bool
    func hasAnyGroup(_ groups: [String]) -> Bool
    func hasAllRoles(_ roles: [String]) -> Bool
    func hasAllGroups(_ groups: [String]) -> Bool
    func getRoleBasedFeatures() -> [String]
    func isFeatureEnabled(_ feature: String) -> Bool
}

class SSORoleManager: SSORoleManagerProtocol {
    private let userInfoStore: SSOUserInfoStore

    init(userInfoStore: SSOUserInfoStore) {
        self.userInfoStore = userInfoStore
    }

    // Implementation of role and group checking methods
    // Feature access control based on roles/groups
}
```

### Step 2: Configure App for SSO

#### 2.1 Add URL Scheme to Info.plist

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>heritagesignal</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>heritagesignal</string>
        </array>
    </dict>
</array>
```

#### 2.2 Update AppDelegate for URL Handling

**File**: `Signal/AppLaunch/AppDelegate.swift`

Add URL callback handling:

```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    if url.scheme == "heritagesignal" {
        // Handle AppAuth callback
        return OIDAuthorizationService.handle(url)
    }
    return false
}
```

### Step 3: Modify RegistrationSplashViewController

#### 3.1 Update RegistrationSplashViewController UI

**File**: `Signal/Registration/UserInterface/RegistrationSplashViewController.swift`

Changes:

- Replace the existing "Create Account" and "Transfer Account" buttons with a single "Sign in with Heritage SSO" button
- Add a welcome message section that will be shown after SSO authentication
- Add the original setup buttons that will appear after successful SSO login

#### 3.2 Add SSO Authentication State Management

```swift
enum RegistrationSplashState {
    case initial // Show SSO login button
    case authenticated(SSOUserInfo) // Show welcome message and setup options
    case loading // Show loading indicator during SSO flow
    case error(SSOError) // Show error state with retry option
}

class RegistrationSplashViewController: UIViewController {
    private var currentState: RegistrationSplashState = .initial
    private let ssoService: SSOServiceProtocol

    // UI Components
    private let ssoLoginButton: UIButton
    private let welcomeLabel: UILabel
    private let setupOptionsStackView: UIStackView
    private let createAccountButton: UIButton
    private let transferAccountButton: UIButton
    private let loadingIndicator: UIActivityIndicatorView
    private let errorView: UIView

    // State management methods
    private func updateUI(for state: RegistrationSplashState)
    private func handleSSOLogin()
    private func handleSSOSuccess(_ userInfo: SSOUserInfo)
    private func handleSSOError(_ error: SSOError)
}
```

#### 3.3 Implement SSO Authentication Flow

```swift
private func handleSSOLogin() {
    updateUI(for: .loading)

    ssoService.authenticate()
        .done { [weak self] userInfo in
            self?.handleSSOSuccess(userInfo)
        }
        .catch { [weak self] error in
            self?.handleSSOError(error as? SSOError ?? .networkError(error))
        }
}

private func handleSSOSuccess(_ userInfo: SSOUserInfo) {
    // Store user info for use in registration flow
    userInfoStore.storeUserInfo(userInfo)

    // Update UI to show welcome message and setup options
    updateUI(for: .authenticated(userInfo))
}

private func updateUI(for state: RegistrationSplashState) {
    currentState = state

    switch state {
    case .initial:
        ssoLoginButton.isHidden = false
        welcomeLabel.isHidden = true
        setupOptionsStackView.isHidden = true
        loadingIndicator.isHidden = true
        errorView.isHidden = true

    case .loading:
        ssoLoginButton.isHidden = true
        welcomeLabel.isHidden = true
        setupOptionsStackView.isHidden = true
        loadingIndicator.isHidden = false
        errorView.isHidden = true

    case .authenticated(let userInfo):
        ssoLoginButton.isHidden = true
        welcomeLabel.isHidden = false
        setupOptionsStackView.isHidden = false
        loadingIndicator.isHidden = true
        errorView.isHidden = true

        // Set welcome message
        welcomeLabel.text = "Welcome \(userInfo.name ?? userInfo.email ?? "User")!"

    case .error(let error):
        ssoLoginButton.isHidden = true
        welcomeLabel.isHidden = true
        setupOptionsStackView.isHidden = true
        loadingIndicator.isHidden = true
        errorView.isHidden = false

        // Show error message with retry option
        showErrorView(with: error)
    }
}
```

### Step 4: Create SSO Authentication View Controller

#### 4.1 Create SSO Authentication View Controller

**File**: `Signal/Registration/UserInterface/SSOAuthenticationViewController.swift`

Features:

- Use AppAuth's `OIDAuthState` for OAuth2 authorization code flow
- Leverage AppAuth's built-in web browser for Keycloak login
- Handle authorization callbacks and token management
- Extract access token and user info using AppAuth's token response

#### 4.2 Configure AppAuth Service

```swift
// In SSOService implementation
let configuration = OIDServiceConfiguration(
    authorizationEndpoint: URL(string: SSOConfig.authorizationEndpoint)!,
    tokenEndpoint: URL(string: SSOConfig.tokenEndpoint)!
)

let request = OIDAuthorizationRequest(
    configuration: configuration,
    clientId: SSOConfig.clientId,
    clientSecret: SSOConfig.clientSecret,
    scopes: SSOConfig.scopes,
    redirectURL: URL(string: SSOConfig.redirectURI)!,
    responseType: OIDResponseTypeCode,
    additionalParameters: nil
)
```

### Step 5: Integrate with Registration Flow

#### 5.1 Update Registration Coordinator

**File**: `Signal/Registration/RegistrationCoordinatorImpl.swift`

Changes:

- Modify the flow to start with RegistrationSplashViewController
- Handle SSO authentication state transitions
- Pass SSO user info to subsequent registration steps
- Store user roles and groups for use throughout the app

#### 5.2 Modify Phone Number Entry

**File**: `Signal/Registration/UserInterface/RegistrationPhoneNumberViewController.swift`

Changes:

- Pre-populate phone number field with SSO data
- Add visual indicator that phone number came from SSO
- Allow user to edit pre-populated number

### Step 6: Handle User Info and Roles

#### 6.1 Parse Keycloak User Info Response

```swift
struct KeycloakUserInfo: Codable {
    let sub: String
    let email: String?
    let name: String?
    let phoneNumber: String?
    let realmAccess: RealmAccess?
    let resourceAccess: [String: ResourceAccess]?
    let groups: [String]?

    struct RealmAccess: Codable {
        let roles: [String]
    }

    struct ResourceAccess: Codable {
        let roles: [String]
    }
}
```

#### 6.2 Handle Authorization Response

```swift
func handleAuthorizationResponse(_ response: OIDAuthorizationResponse) {
    // Exchange authorization code for tokens
    response.tokenExchangeRequest { request, error in
        guard let request = request else {
            // Handle error
            return
        }

        OIDAuthorizationService.perform(request) { response, error in
            // Handle token response and extract user info
        }
    }
}
```

### Step 7: Error Handling

#### 7.1 Define Error Types

```swift
enum SSOError: Error {
    case networkError(Error)
    case invalidToken
    case userCancelled
    case serverError(String)
    case invalidUserInfo
    case missingPhoneNumber
    case roleAccessDenied
}
```

#### 7.2 Error Handling Strategy

```swift
func handleSSOError(_ error: SSOError) {
    switch error {
    case .userCancelled:
        // User cancelled SSO flow - return to initial state
        updateUI(for: .initial)
    case .networkError:
        // Show retry option
        updateUI(for: .error(error))
    case .invalidToken:
        // Trigger re-authentication
        handleSSOLogin()
    case .missingPhoneNumber:
        // Continue with manual phone number entry
        proceedToRegistration()
    default:
        // Show generic error message
        updateUI(for: .error(error))
    }
}
```

## Testing Checklist

- [ ] RegistrationSplashViewController shows SSO login button initially
- [ ] SSO login flow completes successfully
- [ ] Welcome message displays correctly with username
- [ ] Original setup buttons appear after SSO authentication
- [ ] User info is retrieved correctly (phone, roles, groups)
- [ ] Phone number pre-populates in registration
- [ ] Role-based access control works
- [ ] Token refresh works automatically
- [ ] Error scenarios are handled gracefully
- [ ] User can cancel SSO flow and return to initial state
- [ ] App handles network connectivity issues
- [ ] SSO logout clears all data properly

## Keycloak Configuration Requirements

- Configure client `signal_homesteadheritage_org` with redirect URI `heritagesignal://callback`
- Set up scopes: `openid`, `profile`, `email`, `phone`, `roles`, `groups`
- Configure phone number attribute mapping in user profile
- Configure role and group mapping in user profile and client scopes
- Enable PKCE (Proof Key for Code Exchange)
- Configure as public client (no client secret required)
- Ensure roles and groups are included in ID token or userinfo response

## Dependencies

- `AppAuth` (already included in Pods) - For OAuth2 flow and token management
- `SignalServiceKit` - For network requests and data storage
- `SignalUI` - For UI components and theming
- `PromiseKit` - For async operations

## Future Enhancements

1. Support for SSO logout
2. Automatic token refresh
3. Offline authentication support
4. Additional user attributes from SSO
5. SSO status indicators in app settings
6. Role-based UI customization based on user permissions
7. Group-based feature access control
8. Dynamic role/group updates without re-authentication
