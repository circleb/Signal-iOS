import Foundation

public protocol SSOUserInfoStoreProtocol {
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

public class SSOUserInfoStore: SSOUserInfoStoreProtocol {
    public static let shared = SSOUserInfoStore()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let roles = "SSOUserRoles"
        static let groups = "SSOUserGroups"
        static let accessToken = "SSOAccessToken"
        static let refreshToken = "SSORefreshToken"
        static let sub = "SSOUserSub"
        static let email = "SSOUserEmail"
        static let name = "SSOUserName"
        static let phoneNumber = "SSOUserPhoneNumber"
    }

    public func storeUserInfo(_ userInfo: SSOUserInfo) {
        defaults.set(userInfo.roles, forKey: Key.roles)
        defaults.set(userInfo.groups, forKey: Key.groups)
        defaults.set(userInfo.accessToken, forKey: Key.accessToken)
        defaults.set(userInfo.refreshToken, forKey: Key.refreshToken)
        defaults.set(userInfo.sub, forKey: Key.sub)
        defaults.set(userInfo.email, forKey: Key.email)
        defaults.set(userInfo.name, forKey: Key.name)
        defaults.set(userInfo.phoneNumber, forKey: Key.phoneNumber)
    }

    public func getUserInfo() -> SSOUserInfo? {
        guard let roles = defaults.array(forKey: Key.roles) as? [String],
              let accessToken = defaults.string(forKey: Key.accessToken),
              let sub = defaults.string(forKey: Key.sub) else { return nil }

        return SSOUserInfo(
            phoneNumber: defaults.string(forKey: Key.phoneNumber),
            email: defaults.string(forKey: Key.email),
            name: defaults.string(forKey: Key.name),
            sub: sub,
            accessToken: accessToken,
            refreshToken: defaults.string(forKey: Key.refreshToken),
            roles: roles,
            groups: defaults.array(forKey: Key.groups) as? [String] ?? [],
            realmAccess: nil,
            resourceAccess: nil
        )
    }

    public func clearUserInfo() {
        [Key.roles, Key.groups, Key.accessToken, Key.refreshToken,
         Key.sub, Key.email, Key.name, Key.phoneNumber].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    public func getUserRoles() -> [String] { defaults.array(forKey: Key.roles) as? [String] ?? [] }
    public func getUserGroups() -> [String] { defaults.array(forKey: Key.groups) as? [String] ?? [] }
    public func hasRole(_ role: String) -> Bool { getUserRoles().contains(role) }
    public func hasGroup(_ group: String) -> Bool { getUserGroups().contains(group) }
    public func hasAnyRole(_ roles: [String]) -> Bool { roles.contains { hasRole($0) } }
    public func hasAnyGroup(_ groups: [String]) -> Bool { groups.contains { hasGroup($0) } }
}
