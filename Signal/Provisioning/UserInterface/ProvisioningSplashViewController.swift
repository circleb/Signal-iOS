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
    private var ssoLoginButton: OWSFlatButton?
    private var continueButton: OWSFlatButton?
    private var titleLabel: UILabel?

    enum SSOState {
        case initial
        case loading
        case authenticated(SSOUserInfo)
        case error(SSOError)
    }

    override var primaryLayoutMargins: UIEdgeInsets {
        var defaultMargins = super.primaryLayoutMargins
        // we want the hero image a bit closer to the top than most
        // onboarding content
        defaultMargins.top = 16
        return defaultMargins
    }

    override func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        let modeSwitchButton = UIButton()
        view.addSubview(modeSwitchButton)
        modeSwitchButton.setTemplateImageName(
            "link-slash",
            tintColor: .ows_gray25
        )
        modeSwitchButton.autoSetDimensions(to: CGSize(square: 40))
        modeSwitchButton.autoPinEdge(toSuperviewMargin: .trailing)
        modeSwitchButton.autoPinEdge(toSuperviewMargin: .top)
        modeSwitchButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.provisioningController.provisioningSplashRequestedModeSwitch(viewController: self)
        }, for: .touchUpInside)
        modeSwitchButton.accessibilityIdentifier = "onboarding.splash.modeSwitch"

        view.backgroundColor = Theme.backgroundColor

        let heroImage = UIImage(named: "onboarding_splash_hero")
        let heroImageView = UIImageView(image: heroImage)
        heroImageView.contentMode = .scaleAspectFit
        heroImageView.layer.minificationFilter = .trilinear
        heroImageView.layer.magnificationFilter = .trilinear
        heroImageView.setCompressionResistanceLow()
        heroImageView.setContentHuggingVerticalLow()
        heroImageView.accessibilityIdentifier = "onboarding.splash." + "heroImageView"

        let titleLabel = self.createTitleLabel(text: OWSLocalizedString("ONBOARDING_SPLASH_TITLE", comment: "Title of the 'onboarding splash' view."))
        self.titleLabel = titleLabel
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.splash." + "titleLabel"

        if !TSConstants.isUsingProductionService {
            titleLabel.text = "Internal Staging Build" + "\n" + "\(AppVersionImpl.shared.currentAppVersion)"
        }

        let explanationLabel = UILabel()
        explanationLabel.text = OWSLocalizedString("ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                                                  comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view.")
        explanationLabel.textColor = Theme.accentBlueColor
        explanationLabel.font = UIFont.dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(explanationLabelTapped)))
        explanationLabel.accessibilityIdentifier = "onboarding.splash." + "explanationLabel"

        // SSO Login Button (shown when SSO is enabled)
        let ssoLoginButton = self.primaryButton(title: "Sign in with Heritage SSO", action: .init(handler: { [weak self] _ in
            guard let self else { return }
            self.handleSSOLogin()
        }))
        self.ssoLoginButton = ssoLoginButton
        ssoLoginButton.accessibilityIdentifier = "onboarding.splash.ssoLoginButton"
        ssoLoginButton.isHidden = true // Hidden by default, shown when SSO is enabled
        
        let continueButton = self.primaryButton(title: CommonStrings.continueButton, action: .init(handler: { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.provisioningController.provisioningSplashDidComplete(viewController: self)
            }
        }))
        self.continueButton = continueButton
        continueButton.accessibilityIdentifier = "onboarding.splash." + "continueButton"
        
        let primaryButtonView = ProvisioningBaseViewController.horizontallyWrap(primaryButton: continueButton)
        let ssoButtonView = ProvisioningBaseViewController.horizontallyWrap(primaryButton: ssoLoginButton)

        let stackView = UIStackView(arrangedSubviews: [
            heroImageView,
            UIView.spacer(withHeight: 22),
            titleLabel,
            UIView.spacer(withHeight: 92),
            explanationLabel,
            UIView.spacer(withHeight: 24),
            ssoButtonView,
            primaryButtonView
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill

        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
        
        // If SSO was enabled before view loaded, update UI now
        if isSSOEnabled {
            updateSSOUI()
            Logger.info("View loaded and SSO was already enabled - updated UI")
        }
    }

    override func shouldShowBackButton() -> Bool {
        return false
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

    // MARK: - Events

    @objc
    private func explanationLabelTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        let url = TSConstants.legalTermsUrl
        let safariVC = SFSafariViewController(url: url)
        present(safariVC, animated: true)
    }
}
