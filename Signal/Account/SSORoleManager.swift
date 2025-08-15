import Foundation

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

    func getUserRoles() -> [String] {
        return userInfoStore.getUserRoles()
    }

    func getUserGroups() -> [String] {
        return userInfoStore.getUserGroups()
    }

    func hasRole(_ role: String) -> Bool {
        return userInfoStore.hasRole(role)
    }

    func hasGroup(_ group: String) -> Bool {
        return userInfoStore.hasGroup(group)
    }

    func hasAnyRole(_ roles: [String]) -> Bool {
        return userInfoStore.hasAnyRole(roles)
    }

    func hasAnyGroup(_ groups: [String]) -> Bool {
        return userInfoStore.hasAnyGroup(groups)
    }

    func hasAllRoles(_ roles: [String]) -> Bool {
        let userRoles = getUserRoles()
        return roles.allSatisfy { userRoles.contains($0) }
    }

    func hasAllGroups(_ groups: [String]) -> Bool {
        let userGroups = getUserGroups()
        return groups.allSatisfy { userGroups.contains($0) }
    }

    func getRoleBasedFeatures() -> [String] {
        let userRoles = getUserRoles()
        var features: Set<String> = []

        for role in userRoles {
            if let roleFeatures = SSOConfig.roleBasedFeatures[role] {
                features.formUnion(roleFeatures)
            }
        }

        return Array(features)
    }

    func isFeatureEnabled(_ feature: String) -> Bool {
        let availableFeatures = getRoleBasedFeatures()
        return availableFeatures.contains(feature)
    }
} 