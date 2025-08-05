import AppAuth

public struct SSOConfig {
    static let baseURL = "https://auth.homesteadheritage.org"
    static let realm = "heritage"
    static let clientId = "signal_homesteadheritage_org"
    static let clientSecret = "" // Configure if required by Keycloak

    // AppAuth configuration
    static let authorizationEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/auth"
    static let tokenEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/token"
    static let userInfoEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/userinfo"
    static let endSessionEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/logout"

    // OAuth2 scopes - start with standard OpenID Connect scopes
    static let scopes = ["openid", "profile", "email"]

    // Redirect URI
    static let redirectURI = "heritagesignal://oauth/callback"

    // Required roles for access
    static let requiredRoles = ["signal_user", "heritage_member"]
    static let requiredGroups = ["signal_users", "heritage_members"]

    // Feature flags based on roles
    static let roleBasedFeatures: [String: [String]] = [
        "signal_user": ["messaging", "calls", "groups"],
        "heritage_member": ["messaging", "calls", "groups", "heritage_features"],
        "admin": ["messaging", "calls", "groups", "heritage_features", "admin_panel"]
    ]
} 
