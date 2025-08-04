# SSO Integration Plan for Signal App

## Overview

This document outlines the plan to integrate Single Sign-On (SSO) with Keycloak into the Signal app's registration flow. The goal is to present users with an SSO login page immediately when the app opens, and automatically populate the phone number field during onboarding using data from the SSO provider.

## SSO Configuration

- **SSO Provider**: Keycloak
- **Host**: `auth.homesteadheritage.org`
- **Realm**: `heritage`
- **Client ID**: `signal_homesteadheritage_org`
- **User Info Endpoint**: `GET /realms/heritage/protocol/openid-connect/userinfo`

## Current App Flow Analysis

### Current Registration Flow

1. **App Launch**: `AppDelegate.swift` determines launch interface
2. **Registration Splash**: `RegistrationSplashViewController.swift` shows initial welcome screen
3. **Phone Number Entry**: `RegistrationPhoneNumberViewController.swift` handles phone number input
4. **Verification**: SMS verification code entry
5. **Profile Setup**: PIN creation and other setup steps

### Key Files Identified

- `Signal/AppLaunch/AppDelegate.swift` - Determines whether to show registration or main app
- `Signal/Registration/UserInterface/RegistrationSplashViewController.swift` - First screen users see
- `Signal/Registration/UserInterface/RegistrationPhoneNumberViewController.swift` - Phone number entry
- `Signal/Registration/RegistrationCoordinatorImpl.swift` - Manages registration flow
- `Signal/Registration/RegistrationStep.swift` - Defines registration steps

## Proposed SSO Integration Plan

### Phase 1: SSO Authentication Layer

#### 1.1 Create SSO Service

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

#### 1.2 Create SSO Configuration

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

### Phase 2: Modify App Launch Flow

#### 2.1 Update AppDelegate Launch Logic

**File**: `Signal/AppLaunch/AppDelegate.swift`

**Changes**:

- Add SSO check before determining launch interface
- If user is not authenticated via SSO, redirect to SSO flow
- If user is authenticated, proceed with normal registration flow

#### 2.2 Create SSO Authentication View Controller

**File**: `Signal/Registration/UserInterface/SSOAuthenticationViewController.swift`

**Features**:

- Use AppAuth's `OIDAuthState` for OAuth2 authorization code flow
- Leverage AppAuth's built-in web browser for Keycloak login
- Handle authorization callbacks and token management
- Extract access token and user info using AppAuth's token response

### Phase 3: Integrate with Registration Flow

#### 3.1 Add SSO Step to Registration

**File**: `Signal/Registration/RegistrationStep.swift`

**New Step**:

```swift
case ssoAuthentication(SSOAuthenticationState)
```

#### 3.2 Update Registration Coordinator

**File**: `Signal/Registration/RegistrationCoordinatorImpl.swift`

**Changes**:

- Add SSO authentication as first step in registration flow
- Handle SSO success/failure transitions
- Pass SSO user info to subsequent steps

#### 3.3 Modify Phone Number Entry

**File**: `Signal/Registration/UserInterface/RegistrationPhoneNumberViewController.swift`

**Changes**:

- Pre-populate phone number field with SSO data
- Add visual indicator that phone number came from SSO
- Allow user to edit pre-populated number

### Phase 4: Data Flow Integration

#### 4.1 SSO User Info Storage

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

#### 4.2 Role and Group Management

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

#### 4.3 Registration State Updates

**File**: `Signal/Registration/RegistrationCoordinatorImpl.swift`

**Changes**:

- Store SSO user info in registration state
- Use SSO phone number as default in phone number entry
- Handle cases where SSO doesn't provide phone number
- Store user roles and groups for use throughout the app
- Pass role/group information to other app components
- Initialize role manager for app-wide access control

## Implementation Steps

### Step 1: Create SSO Infrastructure

1. Create `SSOService.swift` with Keycloak integration
2. Create `SSOConfig.swift` with configuration constants
3. Create `SSOUserInfoStore.swift` for data persistence with role/group management
4. Add necessary dependencies to project
5. Create `SSORoleManager.swift` for role-based access control throughout the app

### Step 2: Create SSO Authentication UI

1. Create `SSOAuthenticationViewController.swift`
2. Implement AppAuth's OAuth2 authorization code flow using `OIDAuthorizationService`
3. Handle authorization callbacks and token extraction using AppAuth's built-in mechanisms
4. Add proper error handling and user feedback
5. Configure URL scheme handling for OAuth2 redirects

### Step 3: Modify Registration Flow

1. Add SSO step to `RegistrationStep.swift`
2. Update `RegistrationCoordinatorImpl.swift` to handle SSO
3. Modify `RegistrationPhoneNumberViewController.swift` to use SSO data
4. Update navigation flow in `RegistrationNavigationController.swift`

### Step 4: Update App Launch Logic

1. Modify `AppDelegate.swift` to check SSO status
2. Add SSO authentication as prerequisite for registration
3. Handle SSO authentication failures gracefully

### Step 5: Testing and Validation

1. Test SSO authentication flow
2. Verify phone number pre-population
3. Test role and group data retrieval and storage
4. Validate role-based access control functionality
5. Test error scenarios (network issues, invalid tokens, etc.)
6. Validate user experience and flow

## Technical Considerations

### Security

- Use AppAuth's built-in secure token storage mechanisms
- Leverage AppAuth's automatic token refresh capabilities
- Handle token expiration gracefully using AppAuth's state management
- Validate user info responses and token signatures
- Use AppAuth's PKCE (Proof Key for Code Exchange) for enhanced security

### Error Handling

- Network connectivity issues
- Invalid or expired tokens (handled by AppAuth's built-in mechanisms)
- SSO server unavailability
- User cancellation of SSO flow
- AppAuth authorization errors and state management
- Token refresh failures

### User Experience

- Clear indication that SSO is being used
- Seamless transition from AppAuth's web browser to registration
- Fallback options if SSO fails
- Consistent branding with Heritage SSO
- Leverage AppAuth's native iOS web browser experience
- Smooth handling of authorization state transitions

### Data Privacy

- Only request necessary scopes from Keycloak (openid, profile, email, phone, roles, groups)
- Clear SSO data when user logs out using AppAuth's end session endpoint
- Respect user privacy preferences
- Handle cases where phone number is not provided
- Use AppAuth's secure token storage and automatic cleanup
- Ensure role and group data is handled securely and only used for intended purposes

## Dependencies

### External Libraries

- `AppAuth` (already included in Pods) - For OAuth2 authorization code flow, token management, and built-in web browser
- `SafariServices` - For additional web view support if needed

### Internal Dependencies

- `SignalServiceKit` - For network requests and data storage
- `SignalUI` - For UI components and theming
- `PromiseKit` - For async operations

## Configuration Requirements

### Keycloak Setup

- Ensure client `signal_homesteadheritage_org` is properly configured
- Configure redirect URI `heritagesignal://callback` for iOS app
- Set up proper scopes for user info access (openid, profile, email, phone, roles, groups)
- Configure phone number attribute mapping in user profile
- Configure role and group mapping in user profile and client scopes
- Enable PKCE (Proof Key for Code Exchange) for enhanced security
- Configure client as public client (no client secret required for mobile apps)
- Ensure roles and groups are included in the ID token or userinfo response

### iOS App Configuration

- Add URL scheme `heritagesignal` for OAuth2 callbacks in Info.plist
- Configure AppAuth's URL scheme handling in AppDelegate
- Add necessary entitlements for network access
- Configure AppAuth's authorization service in application delegate

## Success Criteria

1. Users are automatically redirected to SSO login when app opens
2. SSO authentication completes successfully
3. Phone number is pre-populated in registration flow
4. User roles and groups are retrieved and stored from SSO
5. Role-based access control works throughout the app
6. User can proceed with normal Signal registration
7. SSO data is properly stored and managed
8. Error scenarios are handled gracefully

## Implementation Notes

### URL Scheme Configuration

#### 1. Add URL Scheme to Info.plist

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

#### 2. Handle URL Callbacks in AppDelegate

```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    if url.scheme == "heritagesignal" {
        // Handle AppAuth callback
        return OIDAuthorizationService.handle(url)
    }
    return false
}
```

### AppAuth Integration Details

#### 3. Configure AppAuth Service

```swift
// In AppDelegate or SSOService initialization
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

#### 4. Handle Authorization Response

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

### Keycloak User Info Response Structure

#### 5. Expected User Info JSON Structure

```json
{
    "sub": "user-id",
    "email": "user@example.com",
    "name": "User Name",
    "phone_number": "+1234567890",
    "realm_access": {
        "roles": ["user", "admin", "moderator"]
    },
    "resource_access": {
        "signal-app": {
            "roles": ["messaging", "admin"]
        }
    },
    "groups": ["group1", "group2", "group3"]
}
```

#### 6. Parse User Info Response

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

### Error Handling Patterns

#### 7. Common Error Scenarios

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

func handleSSOError(_ error: SSOError) {
    switch error {
    case .userCancelled:
        // User cancelled SSO flow - return to registration
    case .networkError:
        // Show retry option
    case .invalidToken:
        // Trigger re-authentication
    case .missingPhoneNumber:
        // Fall back to manual phone number entry
    default:
        // Show generic error message
    }
}
```

### Testing Checklist

#### 8. SSO Integration Testing

- [ ] SSO login flow completes successfully
- [ ] User info is retrieved correctly (phone, roles, groups)
- [ ] Phone number pre-populates in registration
- [ ] Role-based access control works
- [ ] Token refresh works automatically
- [ ] Error scenarios are handled gracefully
- [ ] User can cancel SSO flow and continue manually
- [ ] App handles network connectivity issues
- [ ] SSO logout clears all data properly

## Future Enhancements

1. Support for SSO logout
2. Automatic token refresh
3. Offline authentication support
4. Additional user attributes from SSO
5. SSO status indicators in app settings
6. Role-based UI customization based on user permissions
7. Group-based feature access control
8. Dynamic role/group updates without re-authentication
