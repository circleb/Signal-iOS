//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI
import UIKit

class ProvisioningSplashViewController: ProvisioningBaseViewController {

    // SSO Integration
    private var ssoService: SSOServiceProtocol?
    private var userInfoStore: SSOUserInfoStore?
    private var isSSOEnabled: Bool = false
    private var currentState: SSOState = .initial
    
    // UI References
    private var ssoLoginButton: UIButton?
    private var continueButton: UIButton?
    private var titleLabel: UILabel?

    enum SSOState {
        case initial
        case loading
        case authenticated(SSOUserInfo)
        case error(SSOError)
    }

    var prefersNavigationBarHidden: Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.hidesBackButton = true

        let modeSwitchButton = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.provisioningController.provisioningSplashRequestedModeSwitch(viewController: self)
            }
        )
        modeSwitchButton.configuration?.image = .init(named: "link-slash")
        modeSwitchButton.tintColor = .ows_gray25
        modeSwitchButton.accessibilityIdentifier = "onboarding.splash.modeSwitch"
        view.addSubview(modeSwitchButton)
        modeSwitchButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modeSwitchButton.widthAnchor.constraint(equalToConstant: 40),
            modeSwitchButton.heightAnchor.constraint(equalToConstant: 40),
            modeSwitchButton.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            modeSwitchButton.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
        ])

        // Image at the top.
        let imageView = UIImageView(image: UIImage(named: "onboarding_splash_hero"))
        imageView.contentMode = .scaleAspectFit
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.setCompressionResistanceLow()
        imageView.setContentHuggingVerticalLow()
        imageView.accessibilityIdentifier = "onboarding.splash.heroImageView"
        let heroImageContainer = UIView.container()
        heroImageContainer.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // Center image vertically in the available space above title text.
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: heroImageContainer.centerXAnchor),
            imageView.widthAnchor.constraint(equalTo: heroImageContainer.widthAnchor),
            imageView.centerYAnchor.constraint(equalTo: heroImageContainer.centerYAnchor),
            imageView.heightAnchor.constraint(equalTo: heroImageContainer.heightAnchor, constant: 0.8),
        ])

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
        titleLabel.accessibilityIdentifier = "onboarding.splash." + "titleLabel"
        self.titleLabel = titleLabel

        // Terms of service and privacy policy.
        let tosPPButton = UIButton(
            configuration: .smallBorderless(title: OWSLocalizedString(
                "ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view."
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.present(SFSafariViewController(url: TSConstants.legalTermsUrl), animated: true)
            }
        )
        tosPPButton.configuration?.baseForegroundColor = .Signal.secondaryLabel
        tosPPButton.enableMultilineLabel()
        tosPPButton.accessibilityIdentifier = "onboarding.splash.explanationLabel"

        // SSO Login Button
        let ssoLoginButton = UIButton(
            configuration: .largePrimary(title: "Sign in with Heritage SSO"),
            primaryAction: UIAction { [weak self] _ in
                self?.handleSSOLogin()
            }
        )
        ssoLoginButton.accessibilityIdentifier = "onboarding.splash.ssoLoginButton"
        ssoLoginButton.isHidden = true
        self.ssoLoginButton = ssoLoginButton

        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.provisioningController.provisioningSplashDidComplete(viewController: self)
                }
            }
        )
        continueButton.accessibilityIdentifier = "onboarding.splash.continueButton"
        self.continueButton = continueButton

        let stackView = addStaticContentStackView(arrangedSubviews: [
            heroImageContainer,
            titleLabel,
            tosPPButton,
            ssoLoginButton.enclosedInVerticalStackView(isFullWidthButton: true),
            continueButton.enclosedInVerticalStackView(isFullWidthButton: true),
        ])
        stackView.setCustomSpacing(44, after: imageView)
        stackView.setCustomSpacing(82, after: tosPPButton)

        view.bringSubviewToFront(modeSwitchButton)
        
        // stackView is already added to view via addStaticContentStackView
        // No need to add it again
        
        // If SSO was enabled before view loaded, update UI now
        if isSSOEnabled {
            updateSSOUI()
            Logger.info("View loaded and SSO was already enabled - updated UI")
        }
    }



    // MARK: - SSO Integration

    func enableSSO(ssoService: SSOServiceProtocol, userInfoStore: SSOUserInfoStore) {
        Logger.info("Enabling SSO for ProvisioningSplashViewController")
        
        self.ssoService = ssoService
        self.userInfoStore = userInfoStore
        self.isSSOEnabled = true
        
        // If view is loaded, update UI immediately; otherwise it will be updated in viewDidLoad
        if isViewLoaded {
            updateSSOUI()
            Logger.info("SSO enabled - SSO button: \(ssoLoginButton != nil), Continue button: \(continueButton != nil)")
        } else {
            Logger.info("SSO enabled but view not loaded yet - will update UI when view loads")
        }
    }

    private func updateSSOUI() {
        guard isSSOEnabled else { return }
        
        // Show SSO login button and hide continue button initially
        ssoLoginButton?.isHidden = false
        continueButton?.isHidden = true
        
        Logger.info("SSO UI updated - SSO button visible: \(ssoLoginButton?.isHidden == false), Continue button visible: \(continueButton?.isHidden == false)")
    }

    private func handleSSOLogin() {
        guard let ssoService = ssoService else { return }
        
        currentState = .loading
        updateSSOStateUI()
        
        ssoService.authenticate()
            .done { [weak self] userInfo in
                self?.handleSSOSuccess(userInfo)
            }
            .catch { [weak self] error in
                self?.handleSSOError(error as? SSOError ?? .networkError(error))
            }
    }

    private func handleSSOSuccess(_ userInfo: SSOUserInfo) {
        userInfoStore?.storeUserInfo(userInfo)
        currentState = .authenticated(userInfo)
        updateSSOStateUI()
        
        // Show continue button after successful SSO authentication
        continueButton?.isHidden = false
        ssoLoginButton?.isHidden = true
        
        Logger.info("SSO authentication successful for user: \(userInfo.name ?? "Unknown")")
    }

    private func handleSSOError(_ error: SSOError) {
        currentState = .error(error)
        updateSSOStateUI()
        
        // Show error and allow retry
        let alert = UIAlertController(
            title: "SSO Login Failed",
            message: "Please try again.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.handleSSOLogin()
        })
        
        present(alert, animated: true)
    }

    private func continueWithoutSSO() {
        // Show continue button and hide SSO button
        continueButton?.isHidden = false
        ssoLoginButton?.isHidden = true
        
        Logger.info("Continuing without SSO authentication")
    }

    private func updateSSOStateUI() {
        // Update UI based on current SSO state
        switch currentState {
        case .loading:
            // Show loading indicator
            Logger.info("SSO state: loading")
            break
        case .authenticated(let userInfo):
            // Update title to show welcome message
            let displayName = userInfo.name ?? userInfo.email ?? "User"
            titleLabel?.text = "Welcome, \(displayName)!"
            Logger.info("SSO state: authenticated for \(displayName)")
        case .error(let error):
            // Error UI is handled in handleSSOError
            Logger.warn("SSO state: error - \(error)")
            break
        case .initial:
            Logger.info("SSO state: initial")
            break
        }
    }
}
