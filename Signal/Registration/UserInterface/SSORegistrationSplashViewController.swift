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
    private let ssoLoginButton = OWSFlatButton.primaryButtonForRegistration(
        title: "Sign in with Heritage SSO",
        target: SSORegistrationSplashViewController.self,
        selector: #selector(handleSSOLogin)
    )
    private let welcomeLabel = UILabel()
    private let setupOptionsStackView = UIStackView()
    private let createAccountButton = OWSFlatButton.primaryButtonForRegistration(
        title: "Create Account",
        target: SSORegistrationSplashViewController.self,
        selector: #selector(createAccountPressed)
    )
    private let transferAccountButton = OWSFlatButton.secondaryButtonForRegistration(
        title: "Transfer Account",
        target: SSORegistrationSplashViewController.self,
        selector: #selector(transferAccountPressed)
    )
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let errorView = UIView()
    private let errorLabel = UILabel()
    private let retryButton = OWSFlatButton.primaryButtonForRegistration(
        title: "Retry",
        target: SSORegistrationSplashViewController.self,
        selector: #selector(handleSSOLogin)
    )

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
        let heroImageView = UIImageView(image: heroImage)
        heroImageView.contentMode = .scaleAspectFit
        heroImageView.layer.minificationFilter = .trilinear
        heroImageView.layer.magnificationFilter = .trilinear
        heroImageView.setCompressionResistanceLow()
        heroImageView.setContentHuggingVerticalLow()
        heroImageView.accessibilityIdentifier = "registration.splash.heroImageView"
        stackView.addArrangedSubview(heroImageView)
        stackView.setCustomSpacing(22, after: heroImageView)

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
        titleLabel.accessibilityIdentifier = "registration.splash.titleLabel"
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        // SSO Login Button
        ssoLoginButton.accessibilityIdentifier = "registration.splash.ssoLoginButton"
        stackView.addArrangedSubview(ssoLoginButton)
        ssoLoginButton.autoSetDimension(ALDimension.width, toSize: 280)
        ssoLoginButton.autoHCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            ssoLoginButton.autoPinEdge(toSuperviewEdge: ALEdge.leading)
            ssoLoginButton.autoPinEdge(toSuperviewEdge: ALEdge.trailing)
        }

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
        setupOptionsStackView.spacing = 16
        setupOptionsStackView.accessibilityIdentifier = "registration.splash.setupOptionsStackView"
        stackView.addArrangedSubview(setupOptionsStackView)

        // Create Account Button
        createAccountButton.accessibilityIdentifier = "registration.splash.createAccountButton"
        setupOptionsStackView.addArrangedSubview(createAccountButton)
        createAccountButton.autoSetDimension(ALDimension.width, toSize: 280)
        createAccountButton.autoHCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            createAccountButton.autoPinEdge(toSuperviewEdge: ALEdge.leading)
            createAccountButton.autoPinEdge(toSuperviewEdge: ALEdge.trailing)
        }

        // Transfer Account Button
        transferAccountButton.accessibilityIdentifier = "registration.splash.transferAccountButton"
        setupOptionsStackView.addArrangedSubview(transferAccountButton)
        transferAccountButton.autoSetDimension(ALDimension.width, toSize: 280)
        transferAccountButton.autoHCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            transferAccountButton.autoPinEdge(toSuperviewEdge: ALEdge.leading)
            transferAccountButton.autoPinEdge(toSuperviewEdge: ALEdge.trailing)
        }

        // Loading Indicator
        loadingIndicator.color = Theme.primaryTextColor
        loadingIndicator.accessibilityIdentifier = "registration.splash.loadingIndicator"
        stackView.addArrangedSubview(loadingIndicator)

        // Error View
        errorView.accessibilityIdentifier = "registration.splash.errorView"
        stackView.addArrangedSubview(errorView)

        errorLabel.font = UIFont.dynamicTypeBody
        errorLabel.textColor = .ows_accentRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.accessibilityIdentifier = "registration.splash.errorLabel"
        errorView.addSubview(errorLabel)
        errorLabel.autoPinEdgesToSuperviewMargins()

        retryButton.accessibilityIdentifier = "registration.splash.retryButton"
        errorView.addSubview(retryButton)
        retryButton.autoPinEdge(ALEdge.top, to: ALEdge.bottom, of: errorLabel, withOffset: 16)
        retryButton.autoPinEdge(toSuperviewEdge: ALEdge.bottom)
        retryButton.autoSetDimension(ALDimension.width, toSize: 280)
        retryButton.autoHCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            retryButton.autoPinEdge(toSuperviewEdge: ALEdge.leading)
            retryButton.autoPinEdge(toSuperviewEdge: ALEdge.trailing)
        }

        // Terms and Privacy Policy
        let explanationButton = UIButton()
        explanationButton.setTitle(
            OWSLocalizedString(
                "ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view."
            ),
            for: .normal
        )
        explanationButton.setTitleColor(Theme.secondaryTextAndIconColor, for: .normal)
        explanationButton.titleLabel?.font = UIFont.dynamicTypeBody2
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
            welcomeLabel.isHidden = true
            setupOptionsStackView.isHidden = true
            loadingIndicator.isHidden = true
            errorView.isHidden = true

        case .loading:
            ssoLoginButton.isHidden = true
            welcomeLabel.isHidden = true
            setupOptionsStackView.isHidden = true
            loadingIndicator.isHidden = false
            errorView.isHidden = true
            loadingIndicator.startAnimating()

        case .authenticated(let userInfo):
            ssoLoginButton.isHidden = true
            welcomeLabel.isHidden = false
            setupOptionsStackView.isHidden = false
            loadingIndicator.isHidden = true
            errorView.isHidden = true
            loadingIndicator.stopAnimating()

            // Set welcome message
            let displayName = userInfo.name ?? userInfo.email ?? "User"
            welcomeLabel.text = "Welcome \(displayName)!"

        case .error(let error):
            ssoLoginButton.isHidden = true
            welcomeLabel.isHidden = true
            setupOptionsStackView.isHidden = true
            loadingIndicator.isHidden = true
            errorView.isHidden = false
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

        let hasDeviceButton = RegistrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'have my old device' choice of the 'Restore or Transfer' prompt"
            ),
            body: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'have old device' flow for the 'Restore or Transfer' prompt"
            ),
            iconName: Theme.iconName(.qrCodeLight)
        )
        hasDeviceButton.addTarget(target: self, selector: #selector(hasDevice))
        stackView.addArrangedSubview(hasDeviceButton)

        let noDeviceButton = RegistrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'do not have my old device' choice of the 'Restore or Transfer' prompt"
            ),
            body: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'do not have old device' flow for the 'Restore or Transfer' prompt"
            ),
            iconName: Theme.iconName(.noDevice)
        )
        noDeviceButton.addTarget(target: self, selector: #selector(noDevice))
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
#Preview {
    let presenter = PreviewSSORegistrationSplashPresenter()
    let userInfoStore = SSOUserInfoStoreImpl()
    let ssoService = SSOService(userInfoStore: userInfoStore)
    return SSORegistrationSplashViewController(
        presenter: presenter,
        ssoService: ssoService,
        userInfoStore: userInfoStore
    )
}
#endif 
