//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class SSOAccountSettingsViewController: OWSTableViewController2 {

    private let userInfoStore: SSOUserInfoStore
    private let ssoService: SSOServiceProtocol

    init(userInfoStore: SSOUserInfoStore, ssoService: SSOServiceProtocol) {
        self.userInfoStore = userInfoStore
        self.ssoService = ssoService
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_SSO_ACCOUNT", comment: "Title for the Heritage SSO account settings.")

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
        tableView.layoutIfNeeded()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        if let userInfo = userInfoStore.getUserInfo() {
            // User is logged in - show account information
            let accountSection = OWSTableSection()
            accountSection.headerTitle = OWSLocalizedString("SETTINGS_SSO_ACCOUNT_INFO", comment: "Header for SSO account information section.")

            // Name
            if let name = userInfo.name {
                accountSection.add(.item(
                    icon: .settingsAccount,
                    name: OWSLocalizedString("SETTINGS_SSO_NAME", comment: "Label for SSO account name"),
                    value: name
                ))
            }

            // Email
            if let email = userInfo.email {
                accountSection.add(.item(
                    icon: .settingsAccount,
                    name: OWSLocalizedString("SETTINGS_SSO_EMAIL", comment: "Label for SSO account email"),
                    value: email
                ))
            }

            // Phone Number
            if let phoneNumber = userInfo.phoneNumber {
                accountSection.add(.item(
                    icon: .settingsAccount,
                    name: OWSLocalizedString("SETTINGS_SSO_PHONE", comment: "Label for SSO account phone number"),
                    value: PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(phoneNumber)
                ))
            }

            // User ID
            accountSection.add(.item(
                icon: .settingsAccount,
                name: OWSLocalizedString("SETTINGS_SSO_USER_ID", comment: "Label for SSO account user ID"),
                value: userInfo.sub
            ))

            contents.add(accountSection)

            // Roles Section
            if !userInfo.roles.isEmpty {
                let rolesSection = OWSTableSection()
                rolesSection.headerTitle = OWSLocalizedString("SETTINGS_SSO_ROLES", comment: "Header for SSO roles section.")
                rolesSection.footerTitle = OWSLocalizedString("SETTINGS_SSO_ROLES_FOOTER", comment: "Footer explaining SSO roles.")

                for role in userInfo.roles.sorted() {
                    rolesSection.add(.item(
                        icon: .settingsAccount,
                        name: role,
                        value: nil
                    ))
                }

                contents.add(rolesSection)
            }

            // Groups Section
            if !userInfo.groups.isEmpty {
                let groupsSection = OWSTableSection()
                groupsSection.headerTitle = OWSLocalizedString("SETTINGS_SSO_GROUPS", comment: "Header for SSO groups section.")
                groupsSection.footerTitle = OWSLocalizedString("SETTINGS_SSO_GROUPS_FOOTER", comment: "Footer explaining SSO groups.")

                for group in userInfo.groups.sorted() {
                    groupsSection.add(.item(
                        icon: .settingsAccount,
                        name: group,
                        value: nil
                    ))
                }

                contents.add(groupsSection)
            }

            // Actions Section
            let actionsSection = OWSTableSection()
            actionsSection.headerTitle = OWSLocalizedString("SETTINGS_SSO_ACTIONS", comment: "Header for SSO account actions section.")

            actionsSection.add(.actionItem(
                withText: OWSLocalizedString("SETTINGS_SSO_SIGN_OUT", comment: "Label for SSO sign out button"),
                textColor: .ows_accentRed,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "sso_sign_out"),
                actionBlock: { [weak self] in
                    self?.showSignOutConfirmation()
                }
            ))

            contents.add(actionsSection)

        } else {
            // User is not logged in - show login option
            let loginSection = OWSTableSection()
            loginSection.headerTitle = OWSLocalizedString("SETTINGS_SSO_LOGIN", comment: "Header for SSO login section.")
            loginSection.footerTitle = OWSLocalizedString("SETTINGS_SSO_LOGIN_FOOTER", comment: "Footer explaining SSO login.")

            loginSection.add(.actionItem(
                withText: OWSLocalizedString("SETTINGS_SSO_SIGN_IN", comment: "Label for SSO sign in button"),
                textColor: .ows_accentBlue,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "sso_sign_in"),
                actionBlock: { [weak self] in
                    self?.handleSSOLogin()
                }
            ))

            contents.add(loginSection)
        }

        self.contents = contents
    }

    // MARK: - Actions

    private func showSignOutConfirmation() {
        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString("SETTINGS_SSO_SIGN_OUT_CONFIRMATION_TITLE", comment: "Title for SSO sign out confirmation dialog"),
            message: OWSLocalizedString("SETTINGS_SSO_SIGN_OUT_CONFIRMATION_MESSAGE", comment: "Message for SSO sign out confirmation dialog"),
            proceedTitle: OWSLocalizedString("SETTINGS_SSO_SIGN_OUT", comment: "Label for SSO sign out button"),
            proceedStyle: .destructive
        ) { [weak self] _ in
            self?.handleSSOSignOut()
        }
    }

    private func handleSSOLogin() {
        let loadingAlert = UIAlertController(
            title: OWSLocalizedString("SETTINGS_SSO_LOGGING_IN", comment: "Title for SSO login loading dialog"),
            message: OWSLocalizedString("SETTINGS_SSO_LOGGING_IN_MESSAGE", comment: "Message for SSO login loading dialog"),
            preferredStyle: .alert
        )

        present(loadingAlert, animated: true) { [weak self] in
            self?.performSSOLogin()
        }
    }

    private func performSSOLogin() {
        ssoService.authenticate()
            .done { [weak self] userInfo in
                DispatchQueue.main.async {
                    self?.dismiss(animated: true) {
                        self?.handleSSOLoginSuccess(userInfo)
                    }
                }
            }
            .catch { [weak self] error in
                DispatchQueue.main.async {
                    self?.dismiss(animated: true) {
                        self?.handleSSOLoginError(error)
                    }
                }
            }
    }

    private func handleSSOLoginSuccess(_ userInfo: SSOUserInfo) {
        // Update the table contents to show the logged-in state
        updateTableContents()
        
        // Show success message
        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString("SETTINGS_SSO_LOGIN_SUCCESS_TITLE", comment: "Title for SSO login success"),
            message: String(format: OWSLocalizedString("SETTINGS_SSO_LOGIN_SUCCESS_MESSAGE", comment: "Message for SSO login success"), userInfo.name ?? userInfo.email ?? "User")
        )
    }

    private func handleSSOLoginError(_ error: Error) {
        let errorMessage: String
        if let ssoError = error as? SSOError {
            switch ssoError {
            case .userCancelled:
                // User cancelled, no need to show error
                return
            case .networkError:
                errorMessage = OWSLocalizedString("SETTINGS_SSO_LOGIN_NETWORK_ERROR", comment: "Network error during SSO login")
            case .invalidToken:
                errorMessage = OWSLocalizedString("SETTINGS_SSO_LOGIN_TOKEN_ERROR", comment: "Token error during SSO login")
            case .serverError(let message):
                errorMessage = String(format: OWSLocalizedString("SETTINGS_SSO_LOGIN_SERVER_ERROR", comment: "Server error during SSO login"), message)
            case .invalidUserInfo:
                errorMessage = OWSLocalizedString("SETTINGS_SSO_LOGIN_USER_INFO_ERROR", comment: "User info error during SSO login")
            case .missingPhoneNumber:
                errorMessage = OWSLocalizedString("SETTINGS_SSO_LOGIN_PHONE_ERROR", comment: "Phone number error during SSO login")
            case .roleAccessDenied:
                errorMessage = OWSLocalizedString("SETTINGS_SSO_LOGIN_ROLE_ERROR", comment: "Role access error during SSO login")
            case .configurationError:
                errorMessage = OWSLocalizedString("SETTINGS_SSO_LOGIN_CONFIG_ERROR", comment: "Configuration error during SSO login")
            }
        } else {
            errorMessage = OWSLocalizedString("SETTINGS_SSO_LOGIN_UNKNOWN_ERROR", comment: "Unknown error during SSO login")
        }

        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString("SETTINGS_SSO_LOGIN_ERROR_TITLE", comment: "Title for SSO login error"),
            message: errorMessage
        )
    }

    private func handleSSOSignOut() {
        let loadingAlert = UIAlertController(
            title: OWSLocalizedString("SETTINGS_SSO_SIGNING_OUT", comment: "Title for SSO sign out loading dialog"),
            message: OWSLocalizedString("SETTINGS_SSO_SIGNING_OUT_MESSAGE", comment: "Message for SSO sign out loading dialog"),
            preferredStyle: .alert
        )

        present(loadingAlert, animated: true) { [weak self] in
            self?.performSSOSignOut()
        }
    }

    private func performSSOSignOut() {
        ssoService.signOut()
            .done { [weak self] in
                DispatchQueue.main.async {
                    self?.dismiss(animated: true) {
                        self?.handleSSOSignOutSuccess()
                    }
                }
            }
            .catch { [weak self] error in
                DispatchQueue.main.async {
                    self?.dismiss(animated: true) {
                        self?.handleSSOSignOutError(error)
                    }
                }
            }
    }

    private func handleSSOSignOutSuccess() {
        // Update the table contents to show the logged-out state
        updateTableContents()
        
        // Show success message
        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString("SETTINGS_SSO_SIGN_OUT_SUCCESS_TITLE", comment: "Title for SSO sign out success"),
            message: OWSLocalizedString("SETTINGS_SSO_SIGN_OUT_SUCCESS_MESSAGE", comment: "Message for SSO sign out success")
        )
    }

    private func handleSSOSignOutError(_ error: Error) {
        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString("SETTINGS_SSO_SIGN_OUT_ERROR_TITLE", comment: "Title for SSO sign out error"),
            message: OWSLocalizedString("SETTINGS_SSO_SIGN_OUT_ERROR_MESSAGE", comment: "Message for SSO sign out error")
        )
    }
}
