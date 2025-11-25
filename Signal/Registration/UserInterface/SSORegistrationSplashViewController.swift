//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SafariServices
import SignalServiceKit
public import SignalUI

// MARK: - SSORegistrationSplashPresenter

public protocol SSORegistrationSplashPresenter: RegistrationSplashPresenter {
    func handleSSOSuccess(_ userInfo: SSOUserInfo)
    func handleSSOError(_ error: SSOError)
}

// MARK: - Registration States

enum RegistrationSplashState {
    case initial // Show SSO login button
    case authenticated(SSOUserInfo) // Show welcome message and setup options
    case loading // Show loading indicator during SSO flow
    case error(SSOError) // Show error state with retry option
}

// MARK: - SSORegistrationSplashViewController

public class SSORegistrationSplashViewController: OWSViewController {

    private weak var presenter: SSORegistrationSplashPresenter?
    private var currentState: RegistrationSplashState = .initial
    private let ssoService: SSOServiceProtocol
    private let userInfoStore: SSOUserInfoStore

    // UI Components
    private let stackView = UIStackView()
    private lazy var ssoLoginButton: UIButton = {
        let button = UIButton(
            configuration: .largePrimary(title: "Sign in with Heritage SSO"),
            primaryAction: UIAction { [weak self] _ in
                self?.handleSSOLogin()
            }
        )
        return button
    }()
    private let howdyLabel = UILabel()
    private let welcomeLabel = UILabel()
    private let setupOptionsStackView = UIStackView()
    private lazy var createAccountButton: UIButton = {
        let button = UIButton(
            configuration: .largePrimary(title: "Configure Chat"),
            primaryAction: UIAction { [weak self] _ in
                self?.createAccountPressed()
            }
        )
        return button
    }()
    private lazy var transferAccountButton: UIButton = {
        var config = UIButton.Configuration.largePrimary(title: "Transfer chats from Signal")
        config.baseBackgroundColor = UIColor.Signal.secondaryFill
        config.baseForegroundColor = UIColor.Signal.secondaryLabel
        let button = UIButton(
            configuration: config,
            primaryAction: UIAction { [weak self] _ in
                self?.transferAccountPressed()
            }
        )
        return button
    }()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let errorView = UIView()
    private let errorLabel = UILabel()
    private lazy var retryButton: UIButton = {
        let button = UIButton(
            configuration: .largePrimary(title: "Retry"),
            primaryAction: UIAction { [weak self] _ in
                self?.handleSSOLogin()
            }
        )
        return button
    }()
    
    // UI elements for dynamic stack view management
    private var heroImageView: UIImageView!
    private var titleLabel: UILabel!
    private var explanationButton: UIButton!

    init(
        presenter: SSORegistrationSplashPresenter,
        ssoService: SSOServiceProtocol,
        userInfoStore: SSOUserInfoStore
    ) {
        self.presenter = presenter
        self.ssoService = ssoService
        self.userInfoStore = userInfoStore
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.setHidesBackButton(true, animated: false)
        view.backgroundColor = Theme.backgroundColor

        setupUI()
        updateUI(for: .initial)
    }

    private func setupUI() {
        // Main stack view
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.directionalLayoutMargins = {
            let horizontalSizeClass = traitCollection.horizontalSizeClass
            var result = NSDirectionalEdgeInsets.layoutMarginsForRegistration(horizontalSizeClass)
            result.top = 16
            return result
        }()
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        // Hero image
        let heroImage = UIImage(named: "onboarding_splash_hero")
        heroImageView = UIImageView(image: heroImage)
        heroImageView.contentMode = .scaleAspectFit
        heroImageView.layer.minificationFilter = .trilinear
        heroImageView.layer.magnificationFilter = .trilinear
        heroImageView.setCompressionResistanceLow()
        heroImageView.setContentHuggingVerticalLow()
        heroImageView.accessibilityIdentifier = "registration.splash.heroImageView"
        stackView.addArrangedSubview(heroImageView)
        stackView.setCustomSpacing(22, after: heroImageView)

        // Howdy Label (shown when authenticated)
        howdyLabel.font = UIFont.dynamicTypeTitle2
        howdyLabel.textColor = Theme.primaryTextColor
        howdyLabel.textAlignment = .center
        howdyLabel.numberOfLines = 0
        howdyLabel.accessibilityIdentifier = "registration.splash.howdyLabel"
        howdyLabel.isHidden = true
        stackView.addArrangedSubview(howdyLabel)
        stackView.setCustomSpacing(8, after: howdyLabel)

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
        titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        titleLabel.accessibilityIdentifier = "registration.splash.titleLabel"
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        // SSO Login Button
        ssoLoginButton.accessibilityIdentifier = "registration.splash.ssoLoginButton"
        stackView.addArrangedSubview(ssoLoginButton.enclosedInVerticalStackView(isFullWidthButton: true))

        // Welcome Label
        welcomeLabel.font = UIFont.dynamicTypeTitle2
        welcomeLabel.textColor = Theme.primaryTextColor
        welcomeLabel.textAlignment = .center
        welcomeLabel.numberOfLines = 0
        welcomeLabel.accessibilityIdentifier = "registration.splash.welcomeLabel"
        stackView.addArrangedSubview(welcomeLabel)
        stackView.setCustomSpacing(16, after: welcomeLabel)

        // Setup Options Stack View
        setupOptionsStackView.axis = .vertical
        setupOptionsStackView.spacing = 8
        setupOptionsStackView.accessibilityIdentifier = "registration.splash.setupOptionsStackView"
        stackView.addArrangedSubview(setupOptionsStackView)

        // Create Account Button
        createAccountButton.accessibilityIdentifier = "registration.splash.createAccountButton"
        setupOptionsStackView.addArrangedSubview(createAccountButton.enclosedInVerticalStackView(isFullWidthButton: true))

        // Transfer Account Button
        transferAccountButton.accessibilityIdentifier = "registration.splash.transferAccountButton"
        setupOptionsStackView.addArrangedSubview(transferAccountButton.enclosedInVerticalStackView(isFullWidthButton: true))

        // Loading Indicator
        loadingIndicator.color = Theme.primaryTextColor
        loadingIndicator.accessibilityIdentifier = "registration.splash.loadingIndicator"
        stackView.addArrangedSubview(loadingIndicator)

        // Error Label - add directly to stack view instead of wrapping in error view
        errorLabel.font = UIFont.dynamicTypeBody
        errorLabel.textColor = .ows_accentRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.accessibilityIdentifier = "registration.splash.errorLabel"
        errorLabel.isHidden = true  // Initially hidden
        stackView.addArrangedSubview(errorLabel)
        
        // Retry Button - add directly to stack view instead of wrapping in error view
        retryButton.accessibilityIdentifier = "registration.splash.retryButton"
        retryButton.isHidden = true  // Initially hidden
        stackView.addArrangedSubview(retryButton)
        
        // Set custom spacing between error label and retry button
        stackView.setCustomSpacing(16, after: errorLabel)
        
        // Set custom spacing after retry button to prevent overlap with terms button
        stackView.setCustomSpacing(24, after: retryButton)

        // Terms and Privacy Policy
        explanationButton = UIButton()
        explanationButton.setTitle(
            OWSLocalizedString(
                "ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view."
            ),
            for: .normal
        )
        explanationButton.setTitleColor(Theme.secondaryTextAndIconColor, for: .normal)
        explanationButton.titleLabel?.font = UIFont.dynamicTypeFootnote
        explanationButton.titleLabel?.numberOfLines = 0
        explanationButton.titleLabel?.textAlignment = .center
        explanationButton.titleLabel?.lineBreakMode = .byWordWrapping
        explanationButton.addTarget(
            self,
            action: #selector(explanationButtonTapped),
            for: .touchUpInside
        )
        explanationButton.accessibilityIdentifier = "registration.splash.explanationLabel"
        stackView.addArrangedSubview(explanationButton)
    }



    private func updateUI(for state: RegistrationSplashState) {
        currentState = state

        switch state {
        case .initial:
            ssoLoginButton.isHidden = false
            howdyLabel.isHidden = true
            welcomeLabel.isHidden = true
            setupOptionsStackView.isHidden = true
            loadingIndicator.isHidden = true
            errorLabel.isHidden = true  // Hide error label
            retryButton.isHidden = true  // Hide retry button
            explanationButton.isHidden = false  // Show terms link in initial state

        case .loading:
            ssoLoginButton.isHidden = true
            howdyLabel.isHidden = true
            welcomeLabel.isHidden = true
            setupOptionsStackView.isHidden = true
            loadingIndicator.isHidden = false
            errorLabel.isHidden = true  // Hide error label
            retryButton.isHidden = true  // Hide retry button
            explanationButton.isHidden = false  // Show terms link in loading state
            loadingIndicator.startAnimating()

        case .authenticated(let userInfo):
            ssoLoginButton.isHidden = true
            howdyLabel.isHidden = false
            welcomeLabel.isHidden = true
            setupOptionsStackView.isHidden = false
            loadingIndicator.isHidden = true
            errorLabel.isHidden = true  // Hide error label
            retryButton.isHidden = true  // Hide retry button
            loadingIndicator.stopAnimating()

            // Set howdy message
            let displayName = userInfo.name ?? userInfo.email ?? "User"
            howdyLabel.text = "Howdy \(displayName)!"
            
            // Show terms link in authenticated state
            explanationButton.isHidden = false

        case .error(let error):
            ssoLoginButton.isHidden = true
            howdyLabel.isHidden = true
            welcomeLabel.isHidden = true
            setupOptionsStackView.isHidden = true
            loadingIndicator.isHidden = true
            errorLabel.isHidden = false  // Show error label directly
            retryButton.isHidden = false  // Show retry button directly
            explanationButton.isHidden = true  // Hide terms link in error state
            loadingIndicator.stopAnimating()

            // Show error message
            switch error {
            case .userCancelled:
                errorLabel.text = "SSO login was cancelled. Please try again."
            case .networkError:
                errorLabel.text = "Network error. Please check your connection and try again."
            case .invalidToken:
                errorLabel.text = "Authentication failed. Please try again."
            case .missingPhoneNumber:
                errorLabel.text = "Phone number not found in SSO profile. Please continue with manual entry."
            default:
                errorLabel.text = "An error occurred during SSO login. Please try again."
            }
            
            // Force layout update to ensure retry button is visible and properly sized
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    // MARK: - Actions

    @objc
    private func handleSSOLogin() {
        updateUI(for: .loading)

        ssoService.authenticate()
            .done { [weak self] userInfo in
                self?.handleSSOSuccess(userInfo)
            }
            .catch { [weak self] error in
                self?.handleSSOError(error as? SSOError ?? .networkError(error))
            }
    }

    private func handleSSOSuccess(_ userInfo: SSOUserInfo) {
        // Store user info for use in registration flow
        userInfoStore.storeUserInfo(userInfo)

        // Update UI to show welcome message and setup options
        updateUI(for: .authenticated(userInfo))

        // Notify presenter
        presenter?.handleSSOSuccess(userInfo)
    }

    private func handleSSOError(_ error: SSOError) {
        updateUI(for: .error(error))

        // Notify presenter
        presenter?.handleSSOError(error)
    }

    @objc
    private func createAccountPressed() {
        Logger.info("")
        presenter?.continueFromSplash()
    }

    @objc
    private func transferAccountPressed() {
        Logger.info("")
        let sheet = RestoreOrTransferPickerController(
            setHasOldDeviceBlock: { [weak self] hasOldDevice in
                self?.dismiss(animated: true) {
                    self?.presenter?.setHasOldDevice(hasOldDevice)
                }
            }
        )
        self.present(sheet, animated: true)
    }

    @objc
    private func explanationButtonTapped(sender: UIGestureRecognizer) {
        let safariVC = SFSafariViewController(url: TSConstants.legalTermsUrl)
        present(safariVC, animated: true)
    }
    
    // MARK: - Preview Support
    
    #if DEBUG
    /// Sets the preview state for SwiftUI previews
    /// This method is only available in debug builds and should not be used in production
    func setPreviewState(_ state: RegistrationSplashState) {
        updateUI(for: state)
    }
    #endif
}

// MARK: - RestoreOrTransferPickerController

private class RestoreOrTransferPickerController: StackSheetViewController {

    private let setHasOldDeviceBlock: ((Bool) -> Void)
    init(setHasOldDeviceBlock: @escaping (Bool) -> Void) {
        self.setHasOldDeviceBlock = setHasOldDeviceBlock
        super.init()
    }

    open override var sheetBackgroundColor: UIColor { Theme.secondaryBackgroundColor }

    override func viewDidLoad() {
        super.viewDidLoad()
        stackView.spacing = 16

        let hasDeviceButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'have my old device' choice of the 'Restore or Transfer' prompt"
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'have old device' flow for the 'Restore or Transfer' prompt"
            ),
            iconName: Theme.iconName(.qrCodeLight),
            primaryAction: UIAction { [weak self] _ in
                self?.hasDevice()
            }
        )
        stackView.addArrangedSubview(hasDeviceButton)

        let noDeviceButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'do not have my old device' choice of the 'Restore or Transfer' prompt"
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'do not have old device' flow for the 'Restore or Transfer' prompt"
            ),
            iconName: Theme.iconName(.noDevice),
            primaryAction: UIAction { [weak self] _ in
                self?.noDevice()
            }
        )
        stackView.addArrangedSubview(noDeviceButton)
    }

    @objc func hasDevice() {
        setHasOldDeviceBlock(true)
    }

    @objc func noDevice() {
        setHasOldDeviceBlock(false)
    }
}

#if DEBUG
private class PreviewSSORegistrationSplashPresenter: SSORegistrationSplashPresenter {
    func continueFromSplash() {
        print("continueFromSplash")
    }

    func setHasOldDevice(_ hasOldDevice: Bool) {
        print("setHasOldDevice: \(hasOldDevice)")
    }

    func switchToDeviceLinkingMode() {
        print("switchToDeviceLinkingMode")
    }

    func transferDevice() {
        print("transferDevice")
    }

    func handleSSOSuccess(_ userInfo: SSOUserInfo) {
        print("handleSSOSuccess: \(userInfo.name ?? "Unknown")")
    }

    func handleSSOError(_ error: SSOError) {
        print("handleSSOError: \(error)")
    }
}

@available(iOS 17, *)
#Preview("Initial State") {
    let presenter = PreviewSSORegistrationSplashPresenter()
    let userInfoStore = SSOUserInfoStoreImpl()
    let ssoService = SSOService(userInfoStore: userInfoStore)
    return SSORegistrationSplashViewController(
        presenter: presenter,
        ssoService: ssoService,
        userInfoStore: userInfoStore
    )
}

@available(iOS 17, *)
#Preview("User Cancelled SSO") {
    let presenter = PreviewSSORegistrationSplashPresenter()
    let userInfoStore = SSOUserInfoStoreImpl()
    let ssoService = SSOService(userInfoStore: userInfoStore)
    let viewController = SSORegistrationSplashViewController(
        presenter: presenter,
        ssoService: ssoService,
        userInfoStore: userInfoStore
    )
    
    // Ensure the view is loaded and laid out before setting the preview state
    viewController.loadViewIfNeeded()
    viewController.view.layoutIfNeeded()
    
    // Use the safe preview method to show the user cancelled error state
    viewController.setPreviewState(.error(.userCancelled))
    
    return viewController
}

@available(iOS 17, *)
#Preview("Network Error") {
    let presenter = PreviewSSORegistrationSplashPresenter()
    let userInfoStore = SSOUserInfoStoreImpl()
    let ssoService = SSOService(userInfoStore: userInfoStore)
    let viewController = SSORegistrationSplashViewController(
        presenter: presenter,
        ssoService: ssoService,
        userInfoStore: userInfoStore
    )
    
    // Ensure the view is loaded and laid out before setting the preview state
    viewController.loadViewIfNeeded()
    viewController.view.layoutIfNeeded()
    
    let networkError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: nil)
    viewController.setPreviewState(.error(.networkError(networkError)))
    
    return viewController
}

@available(iOS 17, *)
#Preview("Missing Phone Number") {
    let presenter = PreviewSSORegistrationSplashPresenter()
    let userInfoStore = SSOUserInfoStoreImpl()
    let ssoService = SSOService(userInfoStore: userInfoStore)
    let viewController = SSORegistrationSplashViewController(
        presenter: presenter,
        ssoService: ssoService,
        userInfoStore: userInfoStore
    )
    
    // Ensure the view is loaded and laid out before setting the preview state
    viewController.loadViewIfNeeded()
    viewController.view.layoutIfNeeded()
    
    viewController.setPreviewState(.error(.missingPhoneNumber))
    
    return viewController
}
#endif 
