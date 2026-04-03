import Foundation
import SignalServiceKit

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
    
    // Custom coding keys to handle snake_case to camelCase conversion
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
    init(from keycloakUserInfo: KeycloakUserInfo, accessToken: String, refreshToken: String?) {
        self.phoneNumber = keycloakUserInfo.phoneNumber
        self.email = keycloakUserInfo.email
        self.name = keycloakUserInfo.name
        self.sub = keycloakUserInfo.sub
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        
        // Extract all roles from both realm access and resource access
        var allRoles: [String] = []
        
        // Add realm roles
        if let realmRoles = keycloakUserInfo.realmAccess?.roles {
            Logger.info("SSO: Found realm roles: \(realmRoles)")
            allRoles.append(contentsOf: realmRoles)
        } else {
            Logger.info("SSO: No realm roles found")
        }
        
        // Add resource roles
        if let resourceAccess = keycloakUserInfo.resourceAccess {
            Logger.info("SSO: Found resource access with \(resourceAccess.count) resources")
            for (resourceName, access) in resourceAccess {
                Logger.info("SSO: Resource '\(resourceName)' has roles: \(access.roles)")
                allRoles.append(contentsOf: access.roles)
            }
        } else {
            Logger.info("SSO: No resource access found")
        }
        
        Logger.info("SSO: Total extracted roles: \(allRoles)")
        
        self.roles = allRoles
        self.groups = keycloakUserInfo.groups ?? []
        
        // Store realm access
        self.realmAccess = keycloakUserInfo.realmAccess?.roles.reduce(into: [:]) { result, role in
            result["realm_access"] = [role]
        }
        
        // Store resource access
        self.resourceAccess = keycloakUserInfo.resourceAccess?.reduce(into: [:]) { result, element in
            result[element.key] = element.value.roles
        }
    }
} 
