//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppAuth
import SafariServices
import SignalServiceKit
import SignalUI

// MARK: - RegistrationSSOLoginPresenter

public protocol RegistrationSSOLoginPresenter: AnyObject {
    func ssoLoginDidComplete(withToken accessToken: String)
    func ssoLoginDidFail(withError error: Error)
    func ssoLoginDidCancel()
}

// MARK: - RegistrationSSOLoginViewController

class RegistrationSSOLoginViewController: OWSViewController {
    
    private weak var presenter: RegistrationSSOLoginPresenter?
    private var currentAuthFlow: OIDExternalUserAgentSession?
    
    // SSO Configuration
    private let ssoHost = "auth.homesteadheritage.org"
    private let clientId = "signal_homesteadheritage_org" 
    private let redirectURI = "heritagesignal://callback"
    
    public init(presenter: RegistrationSSOLoginPresenter) {
        self.presenter = presenter
        super.init()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.setHidesBackButton(true, animated: false)
        view.backgroundColor = Theme.backgroundColor
        
        setupUI()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Start SSO authentication flow automatically when view appears
        startSSOAuthentication()
    }
    
    private func setupUI() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 24
        stackView.directionalLayoutMargins = {
            let horizontalSizeClass = traitCollection.horizontalSizeClass
            var result = NSDirectionalEdgeInsets.layoutMarginsForRegistration(horizontalSizeClass)
            result.top = 64
            return result
        }()
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
        
        // Logo
        let logoImageView = UIImageView()
        logoImageView.image = UIImage(named: "signal-logo-128")
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.autoSetDimensions(to: CGSize(width: 80, height: 80))
        logoImageView.accessibilityIdentifier = "registration.sso.logo"
        
        let logoContainer = UIView()
        logoContainer.addSubview(logoImageView)
        logoImageView.autoCenterInSuperview()
        logoContainer.autoSetDimension(.height, toSize: 120)
        stackView.addArrangedSubview(logoContainer)
        
        // Title
        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_SSO_LOGIN_TITLE",
            comment: "Title for the SSO login step during registration"
        ))
        titleLabel.accessibilityIdentifier = "registration.sso.titleLabel"
        stackView.addArrangedSubview(titleLabel)
        
        // Explanation
        let explanationLabel = UILabel()
        explanationLabel.font = .fontForRegistrationExplanationLabel
        explanationLabel.text = OWSLocalizedString(
            "REGISTRATION_SSO_LOGIN_EXPLANATION",
            comment: "Explanation text for the SSO login step during registration"
        )
        explanationLabel.textAlignment = .center
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.numberOfLines = 0
        explanationLabel.accessibilityIdentifier = "registration.sso.explanationLabel"
        stackView.addArrangedSubview(explanationLabel)
        
        // Activity indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = Theme.primaryIconColor
        activityIndicator.startAnimating()
        activityIndicator.accessibilityIdentifier = "registration.sso.activityIndicator"
        
        let activityContainer = UIView()
        activityContainer.addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()
        activityContainer.autoSetDimension(.height, toSize: 80)
        stackView.addArrangedSubview(activityContainer)
        
        // Spacer
        let spacer = UIView()
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stackView.addArrangedSubview(spacer)
        
        // Retry button (initially hidden)
        let retryButton = OWSFlatButton.primaryButtonForRegistration(
            title: OWSLocalizedString(
                "REGISTRATION_SSO_LOGIN_RETRY",
                comment: "Button to retry SSO login during registration"
            ),
            target: self,
            selector: #selector(didTapRetry)
        )
        retryButton.accessibilityIdentifier = "registration.sso.retryButton"
        retryButton.isHidden = true
        stackView.addArrangedSubview(retryButton)
    }
    
    @objc private func didTapRetry() {
        startSSOAuthentication()
    }
    
    private func startSSOAuthentication() {
        // Hide any existing error UI
        view.subviews.forEach { subview in
            if let stackView = subview as? UIStackView {
                stackView.arrangedSubviews.forEach { view in
                    if view.accessibilityIdentifier == "registration.sso.retryButton" {
                        view.isHidden = true
                    }
                    if view.accessibilityIdentifier?.contains("activityIndicator") == true {
                        if let indicator = view.subviews.first as? UIActivityIndicatorView {
                            indicator.startAnimating()
                        }
                    }
                }
            }
        }
        
        // Construct authorization and token endpoints
        let authorizationEndpoint = URL(string: "https://\(ssoHost)/realms/heritage/protocol/openid-connect/auth")!
        let tokenEndpoint = URL(string: "https://\(ssoHost)/realms/heritage/protocol/openid-connect/token")!
        
        // Create service configuration
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint
        )
        
        // Create authorization request
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: clientId,
            scopes: [OIDScopeOpenID, OIDScopeProfile, OIDScopeEmail],
            redirectURL: URL(string: redirectURI)!,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
        
        // Present the authorization request
        currentAuthFlow = OIDAuthState.authState(byPresenting: request, presenting: self) { [weak self] authState, error in
            DispatchQueue.main.async {
                self?.handleAuthorizationResponse(authState: authState, error: error)
            }
        }
    }
    
    private func handleAuthorizationResponse(authState: OIDAuthState?, error: Error?) {
        // Stop activity indicator
        view.subviews.forEach { subview in
            if let stackView = subview as? UIStackView {
                stackView.arrangedSubviews.forEach { view in
                    if view.accessibilityIdentifier?.contains("activityIndicator") == true {
                        if let indicator = view.subviews.first as? UIActivityIndicatorView {
                            indicator.stopAnimating()
                        }
                    }
                }
            }
        }
        
        if let error = error {
            if (error as NSError).code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue {
                // User cancelled
                presenter?.ssoLoginDidCancel()
            } else {
                // Authentication error
                showRetryButton()
                presenter?.ssoLoginDidFail(withError: error)
            }
            return
        }
        
        guard let authState = authState, let accessToken = authState.lastTokenResponse?.accessToken else {
            let ssoError = NSError(domain: "RegistrationSSO", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to obtain access token from SSO"
            ])
            showRetryButton()
            presenter?.ssoLoginDidFail(withError: ssoError)
            return
        }
        
        // Success - pass the access token to the presenter
        presenter?.ssoLoginDidComplete(withToken: accessToken)
    }
    
    private func showRetryButton() {
        view.subviews.forEach { subview in
            if let stackView = subview as? UIStackView {
                stackView.arrangedSubviews.forEach { view in
                    if view.accessibilityIdentifier == "registration.sso.retryButton" {
                        view.isHidden = false
                    }
                }
            }
        }
    }
}

// MARK: - String Extensions for Localization

private extension String {
    static let registrationSSOLoginTitle = OWSLocalizedString(
        "REGISTRATION_SSO_LOGIN_TITLE",
        comment: "Title for the SSO login step during registration"
    )
    
    static let registrationSSOLoginExplanation = OWSLocalizedString(
        "REGISTRATION_SSO_LOGIN_EXPLANATION", 
        comment: "Explanation text for the SSO login step during registration"
    )
    
    static let registrationSSOLoginRetry = OWSLocalizedString(
        "REGISTRATION_SSO_LOGIN_RETRY",
        comment: "Button to retry SSO login during registration"
    )
} 