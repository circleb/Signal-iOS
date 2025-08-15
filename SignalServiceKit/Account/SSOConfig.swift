import AppAuth

public struct SSOConfig {
    public static let baseURL = "https://auth.homesteadheritage.org"
    public static let realm = "heritage"
    public static let clientId = "signal_homesteadheritage_org"
    public static let clientSecret = "" // Configure if required by Keycloak

    // AppAuth configuration
    public static let authorizationEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/auth"
    public static let tokenEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/token"
    public static let userInfoEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/userinfo"
    public static let endSessionEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/logout"

    // OAuth2 scopes - only request scopes that are configured on the Keycloak server
    public static let scopes = [
        "openid", 
        "profile", 
        "email",
        "offline_access",  // For refresh tokens
        "phone",           // For phone number access
        "roles"            // For role-based access control
    ]

    // Redirect URI
    public static let redirectURI = "heritagesignal://oauth/callback"

    // Required roles for access
    public static let requiredRoles = ["heritage-member", "heritage-member-associate"]
    public static let requiredGroups = ["heritage_members"]

    // Feature flags based on roles
    public static let roleBasedFeatures: [String: [String]] = [
        "heritage_member": ["messaging", "calls", "groups", "heritage_features"],
        "admin": ["messaging", "calls", "groups", "heritage_features", "admin_panel"]
    ]
} 
