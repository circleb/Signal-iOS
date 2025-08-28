//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppAuth
import PureLayout
import SignalServiceKit
import SignalUI
import UIKit

// MARK: - SSOAuthenticationViewControllerDelegate

protocol SSOAuthenticationViewControllerDelegate: AnyObject {
    func ssoAuthenticationViewController(_ controller: SSOAuthenticationViewController, didAuthenticate userInfo: SSOUserInfo)
    func ssoAuthenticationViewController(_ controller: SSOAuthenticationViewController, didFailWithError error: SSOError)
    func ssoAuthenticationViewControllerDidCancel(_ controller: SSOAuthenticationViewController)
}

// MARK: - SSOAuthenticationViewController

class SSOAuthenticationViewController: OWSViewController {

    weak var delegate: SSOAuthenticationViewControllerDelegate?
    private let ssoService: SSOServiceProtocol
    private let userInfoStore: SSOUserInfoStore

    // UI Components
    private let stackView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private lazy var loginButton: OWSFlatButton = {
        let button = OWSFlatButton.primaryButtonForRegistration(
            title: "Sign in with Heritage SSO",
            target: self,
            selector: #selector(handleSSOLogin)
        )
        return button
    }()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()
    private lazy var retryButton: OWSFlatButton = {
        let button = OWSFlatButton.primaryButtonForRegistration(
            title: "Retry",
            target: self,
            selector: #selector(handleSSOLogin)
        )
        return button
    }()

    init(ssoService: SSOServiceProtocol, userInfoStore: SSOUserInfoStore) {
        self.ssoService = ssoService
        self.userInfoStore = userInfoStore
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.setHidesBackButton(true, animated: false)
        view.backgroundColor = Theme.backgroundColor

        setupUI()
    }

    private func setupUI() {
        // Main stack view
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 24
        stackView.directionalLayoutMargins = {
            let horizontalSizeClass = traitCollection.horizontalSizeClass
            var result = NSDirectionalEdgeInsets()
            
            switch horizontalSizeClass {
            case .compact:
                // iPhone in portrait or split view
                result.leading = 16
                result.trailing = 16
                result.top = 30
                result.bottom = 20
            case .regular:
                // iPad in landscape or regular split view
                result.leading = 24
                result.trailing = 24
                result.top = 40
                result.bottom = 30
            case .unspecified:
                // Fallback
                result.leading = 20
                result.trailing = 20
                result.top = 35
                result.bottom = 25
            @unknown default:
                // Future cases
                result.leading = 20
                result.trailing = 20
                result.top = 35
                result.bottom = 25
            }
            
            return result
        }()
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        let heroImage = UIImage(named: "onboarding_splash_hero")
        let heroImageView = UIImageView(image: heroImage)
        heroImageView.contentMode = .scaleAspectFit
        heroImageView.layer.minificationFilter = .trilinear
        heroImageView.layer.magnificationFilter = .trilinear
        heroImageView.setCompressionResistanceLow()
        heroImageView.setContentHuggingVerticalLow()
        heroImageView.accessibilityIdentifier = "onboarding.splash." + "heroImageView"
        stackView.addArrangedSubview(heroImageView)

        // Title
        let titleText = {
            if TSConstants.isUsingProductionService {
                return OWSLocalizedString(
                    "ONBOARDING_SPLASH_TITLE",
                    comment: "Title of the 'onboarding splash' view."
                )
            } else {
                return "Internal Staging Build\n\(AppVersionImpl.shared.currentAppVersion)"
            }
        }()
        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        titleLabel.font = UIFont.dynamicTypeTitle1
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center
        titleLabel.accessibilityIdentifier = "registration.splash.titleLabel"
        stackView.addArrangedSubview(titleLabel)

        // Subtitle
        subtitleLabel.text = "Sign in with your Heritage account to get started"
        subtitleLabel.font = UIFont.dynamicTypeBody
        subtitleLabel.textColor = Theme.secondaryTextAndIconColor
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.accessibilityIdentifier = "sso.auth.subtitleLabel"
        stackView.addArrangedSubview(subtitleLabel)

        // Login Button
        loginButton.accessibilityIdentifier = "sso.auth.loginButton"
        stackView.addArrangedSubview(loginButton)
        loginButton.autoSetDimension(ALDimension.width, toSize: 280)
        loginButton.autoHCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            loginButton.autoPinEdge(toSuperviewEdge: ALEdge.leading)
            loginButton.autoPinEdge(toSuperviewEdge: ALEdge.trailing)
        }

        // Loading Indicator
        loadingIndicator.color = Theme.primaryTextColor
        loadingIndicator.accessibilityIdentifier = "sso.auth.loadingIndicator"
        stackView.addArrangedSubview(loadingIndicator)

        // Error Label
        errorLabel.font = UIFont.dynamicTypeBody
        errorLabel.textColor = .ows_accentRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.accessibilityIdentifier = "sso.auth.errorLabel"
        stackView.addArrangedSubview(errorLabel)

        // Retry Button
        retryButton.accessibilityIdentifier = "sso.auth.retryButton"
        stackView.addArrangedSubview(retryButton)
        retryButton.autoSetDimension(ALDimension.width, toSize: 280)
        retryButton.autoHCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            retryButton.autoPinEdge(toSuperviewEdge: ALEdge.leading)
            retryButton.autoPinEdge(toSuperviewEdge: ALEdge.trailing)
        }

        // Initially hide loading and error components
        loadingIndicator.isHidden = true
        errorLabel.isHidden = true
        retryButton.isHidden = true
    }



    // MARK: - Actions

    @objc
    private func handleSSOLogin() {
        showLoadingState()

        ssoService.authenticate()
            .done { [weak self] userInfo in
                self?.handleSSOSuccess(userInfo)
            }
            .catch { [weak self] error in
                self?.handleSSOError(error as? SSOError ?? .networkError(error))
            }
    }

    private func handleSSOSuccess(_ userInfo: SSOUserInfo) {
        // Store user info
        userInfoStore.storeUserInfo(userInfo)

        // Notify delegate
        delegate?.ssoAuthenticationViewController(self, didAuthenticate: userInfo)
    }

    private func handleSSOError(_ error: SSOError) {
        showErrorState(error)
        delegate?.ssoAuthenticationViewController(self, didFailWithError: error)
    }

    // MARK: - UI State Management

    private func showLoadingState() {
        loginButton.isHidden = true
        loadingIndicator.isHidden = false
        errorLabel.isHidden = true
        retryButton.isHidden = true
        loadingIndicator.startAnimating()
    }

    private func showErrorState(_ error: SSOError) {
        loginButton.isHidden = true
        loadingIndicator.isHidden = true
        errorLabel.isHidden = false
        retryButton.isHidden = false
        loadingIndicator.stopAnimating()

        switch error {
        case .userCancelled:
            errorLabel.text = "SSO login was cancelled. Please try again."
            delegate?.ssoAuthenticationViewControllerDidCancel(self)
        case .networkError:
            errorLabel.text = "Network error. Please check your connection and try again."
        case .invalidToken:
            errorLabel.text = "Authentication failed. Please try again."
        case .missingPhoneNumber:
            errorLabel.text = "Phone number not found in SSO profile. Please continue with manual entry."
        case .configurationError:
            errorLabel.text = "SSO configuration error. Please contact support."
        default:
            errorLabel.text = "An error occurred during SSO login. Please try again."
        }
    }

    private func showInitialState() {
        loginButton.isHidden = false
        loadingIndicator.isHidden = true
        errorLabel.isHidden = true
        retryButton.isHidden = true
        loadingIndicator.stopAnimating()
    }
}

#if DEBUG
import SwiftUI

private class PreviewSSOAuthenticationViewControllerDelegate: SSOAuthenticationViewControllerDelegate {
    func ssoAuthenticationViewController(_ controller: SSOAuthenticationViewController, didAuthenticate userInfo: SSOUserInfo) {
        print("SSO Authentication successful: \(userInfo.name ?? "Unknown")")
    }

    func ssoAuthenticationViewController(_ controller: SSOAuthenticationViewController, didFailWithError error: SSOError) {
        print("SSO Authentication failed: \(error)")
    }

    func ssoAuthenticationViewControllerDidCancel(_ controller: SSOAuthenticationViewController) {
        print("SSO Authentication cancelled")
    }
}

@available(iOS 17, *)
#Preview {
    let delegate = PreviewSSOAuthenticationViewControllerDelegate()
    let userInfoStore = SSOUserInfoStoreImpl()
    let ssoService = SSOService(userInfoStore: userInfoStore)
    let controller = SSOAuthenticationViewController(ssoService: ssoService, userInfoStore: userInfoStore)
    controller.delegate = delegate
    return controller
}
#endif 