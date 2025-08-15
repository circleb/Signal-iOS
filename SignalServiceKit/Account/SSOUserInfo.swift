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
public struct KeycloakUserInfo: Codable {
    public let sub: String
    public let email: String?
    public let name: String?
    public let givenName: String?
    public let familyName: String?
    public let preferredUsername: String?
    public let emailVerified: Bool?
    public let phoneNumber: String?
    public let realmAccess: RealmAccess?
    public let resourceAccess: [String: ResourceAccess]?
    public let groups: [String]?

    public struct RealmAccess: Codable {
        public let roles: [String]
        
        public init(roles: [String]) {
            self.roles = roles
        }
    }

    public struct ResourceAccess: Codable {
        public let roles: [String]
        
        public init(roles: [String]) {
            self.roles = roles
        }
    }
    
    public init(sub: String, email: String?, name: String?, givenName: String?, familyName: String?, preferredUsername: String?, emailVerified: Bool?, phoneNumber: String?, realmAccess: RealmAccess?, resourceAccess: [String: ResourceAccess]?, groups: [String]?) {
        self.sub = sub
        self.email = email
        self.name = name
        self.givenName = givenName
        self.familyName = familyName
        self.preferredUsername = preferredUsername
        self.emailVerified = emailVerified
        self.phoneNumber = phoneNumber
        self.realmAccess = realmAccess
        self.resourceAccess = resourceAccess
        self.groups = groups
    }
    
    // Custom coding keys to handle snake_case to camelCase conversion
    public enum CodingKeys: String, CodingKey {
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
    public init(from keycloakUserInfo: KeycloakUserInfo, accessToken: String, refreshToken: String?) {
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
