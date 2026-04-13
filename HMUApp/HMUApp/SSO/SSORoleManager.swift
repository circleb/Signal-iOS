import Foundation

class SSORoleManager {
    private let store: SSOUserInfoStoreProtocol

    init(store: SSOUserInfoStoreProtocol = SSOUserInfoStore.shared) {
        self.store = store
    }

    func getUserRoles() -> [String] { store.getUserRoles() }
    func getUserGroups() -> [String] { store.getUserGroups() }
    func hasRole(_ role: String) -> Bool { store.hasRole(role) }
    func hasGroup(_ group: String) -> Bool { store.hasGroup(group) }
    func hasAnyRole(_ roles: [String]) -> Bool { store.hasAnyRole(roles) }
    func hasAnyGroup(_ groups: [String]) -> Bool { store.hasAnyGroup(groups) }
    func hasAllRoles(_ roles: [String]) -> Bool { roles.allSatisfy { store.hasRole($0) } }
    func hasAllGroups(_ groups: [String]) -> Bool { groups.allSatisfy { store.hasGroup($0) } }

    func getRoleBasedFeatures() -> [String] {
        var features = Set<String>()
        for role in getUserRoles() {
            SSOConfig.roleBasedFeatures[role]?.forEach { features.insert($0) }
        }
        return Array(features)
    }

    func isFeatureEnabled(_ feature: String) -> Bool {
        getRoleBasedFeatures().contains(feature)
    }
}
