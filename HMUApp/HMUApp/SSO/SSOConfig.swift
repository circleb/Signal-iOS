import Foundation

public struct SSOConfig {
    static let baseURL = "https://auth.homesteadheritage.org"
    static let realm = "heritage"
    static let clientId = "signal_homesteadheritage_org"
    static let clientSecret = ""

    static let authorizationEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/auth"
    static let tokenEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/token"
    static let userInfoEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/userinfo"
    static let endSessionEndpoint = "\(baseURL)/realms/\(realm)/protocol/openid-connect/logout"

    static let scopes = ["openid", "profile", "email", "offline_access", "phone", "roles"]
    static let redirectURI = "hmuchat://oauth/callback"

    static let requiredRoles = ["heritage-member", "heritage-member-associate"]
    static let requiredGroups = ["heritage_members"]

    static let roleBasedFeatures: [String: [String]] = [
        "heritage_member": ["messaging", "calls", "groups", "heritage_features"],
        "admin": ["messaging", "calls", "groups", "heritage_features", "admin_panel"]
    ]
}
