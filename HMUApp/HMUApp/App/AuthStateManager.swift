import Foundation
import SwiftUI

@MainActor
final class AuthStateManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userInfo: SSOUserInfo?

    let ssoService: SSOService

    init(ssoService: SSOService = SSOService()) {
        self.ssoService = ssoService
        // Restore session from previous launch
        if let stored = ssoService.store.getUserInfo() {
            self.userInfo = stored
            self.isAuthenticated = true
        }
    }

    func signIn(_ info: SSOUserInfo) {
        userInfo = info
        isAuthenticated = true
        NotificationCenter.default.post(name: .ssoUserDidSignIn, object: nil)
    }

    func signOut() {
        ssoService.signOut()
        userInfo = nil
        isAuthenticated = false
        NotificationCenter.default.post(name: .ssoUserDidSignOut, object: nil)
    }
}

extension Notification.Name {
    static let ssoUserDidSignIn = Notification.Name("ssoUserDidSignIn")
    static let ssoUserDidSignOut = Notification.Name("ssoUserDidSignOut")
}
