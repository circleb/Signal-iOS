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
    public let realmAccess: [String: [String]]? // Keycloak realm access roles
    public let resourceAccess: [String: [String]]? // Keycloak resource access roles
    
    public init(phoneNumber: String?, email: String?, name: String?, sub: String, accessToken: String, refreshToken: String?, roles: [String], groups: [String], realmAccess: [String: [String]]?, resourceAccess: [String: [String]]?) {
        self.phoneNumber = phoneNumber
        self.email = email
        self.name = name
        self.sub = sub
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.roles = roles
        self.groups = groups
        self.realmAccess = realmAccess
        self.resourceAccess = resourceAccess
    }
}

// Keycloak specific user info structure
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

extension SSOUserInfo {
    init(from keycloakUserInfo: KeycloakUserInfo, accessToken: String, refreshToken: String?) {
        self.phoneNumber = keycloakUserInfo.phoneNumber
        self.email = keycloakUserInfo.email
        self.name = keycloakUserInfo.name
        self.sub = keycloakUserInfo.sub
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.roles = keycloakUserInfo.realmAccess?.roles ?? []
        self.groups = keycloakUserInfo.groups ?? []
        self.realmAccess = keycloakUserInfo.realmAccess?.roles.reduce(into: [:]) { result, role in
            result["realm_access"] = [role]
        }
        self.resourceAccess = keycloakUserInfo.resourceAccess?.reduce(into: [:]) { result, element in
            result[element.key] = element.value.roles
        }
    }
} 