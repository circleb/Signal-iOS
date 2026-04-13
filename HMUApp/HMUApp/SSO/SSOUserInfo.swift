import Foundation

public struct SSOUserInfo {
    public let phoneNumber: String?
    public let email: String?
    public let name: String?
    public let sub: String
    public let accessToken: String
    public let refreshToken: String?
    public let roles: [String]
    public let groups: [String]
    public let realmAccess: [String: [String]]?
    public let resourceAccess: [String: [String]]?
}

// Keycloak-specific response structure
struct KeycloakUserInfo: Codable {
    let sub: String
    let email: String?
    let name: String?
    let givenName: String?
    let familyName: String?
    let preferredUsername: String?
    let emailVerified: Bool?
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

    enum CodingKeys: String, CodingKey {
        case sub, email, name, groups
        case givenName = "given_name"
        case familyName = "family_name"
        case preferredUsername = "preferred_username"
        case emailVerified = "email_verified"
        case phoneNumber = "phone"
        case realmAccess = "realm_access"
        case resourceAccess = "resource_access"
    }
}

extension SSOUserInfo {
    init(from keycloak: KeycloakUserInfo, accessToken: String, refreshToken: String?) {
        self.phoneNumber = keycloak.phoneNumber
        self.email = keycloak.email
        self.name = keycloak.name
        self.sub = keycloak.sub
        self.accessToken = accessToken
        self.refreshToken = refreshToken

        var allRoles: [String] = keycloak.realmAccess?.roles ?? []
        if let resourceAccess = keycloak.resourceAccess {
            for access in resourceAccess.values { allRoles.append(contentsOf: access.roles) }
        }
        self.roles = allRoles
        self.groups = keycloak.groups ?? []
        self.realmAccess = keycloak.realmAccess.map { ["realm_access": $0.roles] }
        self.resourceAccess = keycloak.resourceAccess?.reduce(into: [:]) { $0[$1.key] = $1.value.roles }
    }
}
