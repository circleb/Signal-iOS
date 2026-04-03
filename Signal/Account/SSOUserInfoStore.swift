import Foundation

public protocol SSOUserInfoStore {
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

public class SSOUserInfoStoreImpl: SSOUserInfoStore {
    private let userDefaults = UserDefaults.standard
    private let userInfoKey = "SSOUserInfo"
    private let rolesKey = "SSOUserRoles"
    private let groupsKey = "SSOUserGroups"
    private let accessTokenKey = "SSOAccessToken"
    private let refreshTokenKey = "SSORefreshToken"
    private let subKey = "SSOUserSub"
    private let emailKey = "SSOUserEmail"
    private let nameKey = "SSOUserName"
    private let phoneNumberKey = "SSOUserPhoneNumber"

    public func storeUserInfo(_ userInfo: SSOUserInfo) {
        userDefaults.set(userInfo.roles, forKey: rolesKey)
        userDefaults.set(userInfo.groups, forKey: groupsKey)
        userDefaults.set(userInfo.accessToken, forKey: accessTokenKey)
        userDefaults.set(userInfo.refreshToken, forKey: refreshTokenKey)
        userDefaults.set(userInfo.sub, forKey: subKey)
        userDefaults.set(userInfo.email, forKey: emailKey)
        userDefaults.set(userInfo.name, forKey: nameKey)
        userDefaults.set(userInfo.phoneNumber, forKey: phoneNumberKey)
    }

    public func getUserInfo() -> SSOUserInfo? {
        guard let roles = userDefaults.array(forKey: rolesKey) as? [String],
              let accessToken = userDefaults.string(forKey: accessTokenKey),
              let sub = userDefaults.string(forKey: subKey) else {
            return nil
        }

        let groups = userDefaults.array(forKey: groupsKey) as? [String] ?? []
        let refreshToken = userDefaults.string(forKey: refreshTokenKey)
        let email = userDefaults.string(forKey: emailKey)
        let name = userDefaults.string(forKey: nameKey)
        let phoneNumber = userDefaults.string(forKey: phoneNumberKey)

        return SSOUserInfo(
            phoneNumber: phoneNumber,
            email: email,
            name: name,
            sub: sub,
            accessToken: accessToken,
            refreshToken: refreshToken,
            roles: roles,
            groups: groups,
            realmAccess: nil,
            resourceAccess: nil
        )
    }

    public func clearUserInfo() {
        userDefaults.removeObject(forKey: rolesKey)
        userDefaults.removeObject(forKey: groupsKey)
        userDefaults.removeObject(forKey: accessTokenKey)
        userDefaults.removeObject(forKey: refreshTokenKey)
        userDefaults.removeObject(forKey: subKey)
        userDefaults.removeObject(forKey: emailKey)
        userDefaults.removeObject(forKey: nameKey)
        userDefaults.removeObject(forKey: phoneNumberKey)
    }

    public func getUserRoles() -> [String] {
        return userDefaults.array(forKey: rolesKey) as? [String] ?? []
    }

    public func getUserGroups() -> [String] {
        return userDefaults.array(forKey: groupsKey) as? [String] ?? []
    }

    public func hasRole(_ role: String) -> Bool {
        return getUserRoles().contains(role)
    }

    public func hasGroup(_ group: String) -> Bool {
        return getUserGroups().contains(group)
    }

    public func hasAnyRole(_ roles: [String]) -> Bool {
        let userRoles = getUserRoles()
        return roles.contains { userRoles.contains($0) }
    }

    public func hasAnyGroup(_ groups: [String]) -> Bool {
        let userGroups = getUserGroups()
        return groups.contains { userGroups.contains($0) }
    }
} 