//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalServiceKit
import SignalUI

class SSOAccountMenuActions {
    
    private let userInfoStore: SSOUserInfoStore
    private let ssoService: SSOServiceProtocol
    private weak var presentingViewController: UIViewController?
    
    init(userInfoStore: SSOUserInfoStore = SSOUserInfoStoreImpl(),
         ssoService: SSOServiceProtocol,
         presentingViewController: UIViewController?) {
        self.userInfoStore = userInfoStore
        self.ssoService = ssoService
        self.presentingViewController = presentingViewController
    }
    
    func createMenuActions() -> [UIAction] {
        var actions: [UIAction] = []
        
        // User Info Section
        if let userInfo = userInfoStore.getUserInfo() {
            actions.append(createUserInfoAction(userInfo: userInfo))
        }
        
        // Account Management
        actions.append(createAccountManagementAction())
        
        // Sign Out
        actions.append(createSignOutAction())
        
        return actions
    }
    
    private func createUserInfoAction(userInfo: SSOUserInfo) -> UIAction {
        let title: String
        if let name = userInfo.name, !name.isEmpty {
            title = name
        } else if let email = userInfo.email, !email.isEmpty {
            title = email
        } else {
            title = "Unknown User"
        }
        
        let subtitle = userInfo.email ?? "No email"
        
        return UIAction(
            title: "\(title)\n\(subtitle)",
            image: nil,
            attributes: .disabled,
            handler: { _ in }
        )
    }
    
    private func createAccountManagementAction() -> UIAction {
        return UIAction(
            title: "HCP Profile",
            image: UIImage(systemName: "person.crop.circle.fill"),
            handler: { [weak self] _ in
                self?.handleAccountManagement()
            }
        )
    }
    
    private func createSignOutAction() -> UIAction {
        return UIAction(
            title: "Sign Out",
            image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
            attributes: .destructive,
            handler: { [weak self] _ in
                self?.handleSignOut()
            }
        )
    }
    
    private func handleAccountManagement() {
        guard let presentingViewController = presentingViewController else { return }
        
        let accountWebVC = SSOAccountWebViewController()
        let navController = UINavigationController(rootViewController: accountWebVC)
        navController.modalPresentationStyle = .fullScreen
        presentingViewController.present(navController, animated: true)
    }
    
    private func handleSignOut() {
        guard let presentingViewController = presentingViewController else { return }
        
        let alert = UIAlertController(
            title: "Sign Out",
            message: "Are you sure you want to sign out of your SSO account?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in
            self?.performSignOut()
        })
        
        presentingViewController.present(alert, animated: true)
    }
    
    private func performSignOut() {
        // Show loading indicator
        guard let presentingViewController = presentingViewController else { return }
        
        let loadingAlert = UIAlertController(title: "Signing Out...", message: nil, preferredStyle: .alert)
        let loadingIndicator = UIActivityIndicatorView(style: .medium)
        loadingIndicator.startAnimating()
        loadingAlert.view.addSubview(loadingIndicator)
        loadingIndicator.autoCenterInSuperview()
        
        presentingViewController.present(loadingAlert, animated: true)
        
        // Perform sign out
        ssoService.signOut()
            .done { [weak self] in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self?.handleSignOutSuccess()
                    }
                }
            }
            .catch { [weak self] error in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self?.handleSignOutError(error)
                    }
                }
            }
    }
    
    private func handleSignOutSuccess() {
        // Post notification for UI updates first
        NotificationCenter.default.post(name: .ssoUserDidSignOut, object: nil)
        
        // The WebAppsListViewController will handle showing the sign-in overlay
        // via the notification observer, so we don't need to show a success alert
    }
    
    private func handleSignOutError(_ error: Error) {
        guard let presentingViewController = presentingViewController else { return }
        
        let errorAlert = UIAlertController(
            title: "Sign Out Failed",
            message: "An error occurred while signing out: \(error.localizedDescription)",
            preferredStyle: .alert
        )
        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
        presentingViewController.present(errorAlert, animated: true)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let ssoUserDidSignOut = Notification.Name("ssoUserDidSignOut")
    static let ssoUserDidSignIn = Notification.Name("ssoUserDidSignIn")
}
