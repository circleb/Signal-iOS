//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

protocol LimitedRegistrationManagerProtocol {
    /// Returns true if the user is in SSO-only registration state
    func isInLimitedRegistrationState(tx: DBReadTransaction) -> Bool
    
    /// Shows onboarding prompt for a specific tab
    func showOnboardingPrompt(for tab: LimitedRegistrationTab, from viewController: UIViewController)
    
    /// Handles tab selection in limited registration state
    func handleTabSelection(_ tab: LimitedRegistrationTab, from viewController: UIViewController) -> Bool
}

enum LimitedRegistrationTab {
    case chats
    case stories
    case calls
    
    var title: String {
        switch self {
        case .chats:
            return OWSLocalizedString(
                "LIMITED_REGISTRATION_CHATS_TITLE",
                comment: "Title for chats tab onboarding prompt"
            )
        case .stories:
            return OWSLocalizedString(
                "LIMITED_REGISTRATION_STORIES_TITLE",
                comment: "Title for stories tab onboarding prompt"
            )
        case .calls:
            return OWSLocalizedString(
                "LIMITED_REGISTRATION_CALLS_TITLE",
                comment: "Title for calls tab onboarding prompt"
            )
        }
    }
    
    var message: String {
        switch self {
        case .chats:
            return OWSLocalizedString(
                "LIMITED_REGISTRATION_CHATS_MESSAGE",
                comment: "Message explaining that chats require full registration"
            )
        case .stories:
            return OWSLocalizedString(
                "LIMITED_REGISTRATION_STORIES_MESSAGE",
                comment: "Message explaining that stories require full registration"
            )
        case .calls:
            return OWSLocalizedString(
                "LIMITED_REGISTRATION_CALLS_MESSAGE",
                comment: "Message explaining that calls require full registration"
            )
        }
    }
}

class LimitedRegistrationManager: LimitedRegistrationManagerProtocol {
    private let tsAccountManager: TSAccountManager
    private let registrationCoordinatorLoader: RegistrationCoordinatorLoader
    private let appReadiness: AppReadinessSetter
    
    init(
        tsAccountManager: TSAccountManager,
        registrationCoordinatorLoader: RegistrationCoordinatorLoader,
        appReadiness: AppReadinessSetter
    ) {
        self.tsAccountManager = tsAccountManager
        self.registrationCoordinatorLoader = registrationCoordinatorLoader
        self.appReadiness = appReadiness
    }
    
    func isInLimitedRegistrationState(tx: DBReadTransaction) -> Bool {
        let registrationState = tsAccountManager.registrationState(tx: tx)
        switch registrationState {
        case .ssoOnly:
            return true
        default:
            return false
        }
    }
    
    func showOnboardingPrompt(for tab: LimitedRegistrationTab, from viewController: UIViewController) {
        let alert = UIAlertController(
            title: tab.title,
            message: tab.message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(
            title: OWSLocalizedString(
                "LIMITED_REGISTRATION_COMPLETE_REGISTRATION",
                comment: "Button to complete full registration"
            ),
            style: .default
        ) { [weak self] _ in
            self?.startFullRegistration(from: viewController)
        })
        
        alert.addAction(UIAlertAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ))
        
        viewController.present(alert, animated: true)
    }
    
    func handleTabSelection(_ tab: LimitedRegistrationTab, from viewController: UIViewController) -> Bool {
        // Check if we're in limited registration state
        let isLimited = SSKEnvironment.shared.databaseStorageRef.read { tx in
            isInLimitedRegistrationState(tx: tx)
        }
        
        if isLimited {
            showOnboardingPrompt(for: tab, from: viewController)
            return false // Prevent normal tab selection
        }
        
        return true // Allow normal tab selection
    }
    
    private func startFullRegistration(from viewController: UIViewController) {
        // Start the full registration flow
        let coordinator = SSKEnvironment.shared.databaseStorageRef.write { tx in
            return registrationCoordinatorLoader.coordinator(forDesiredMode: .registering, transaction: tx)
        }
        
        let navController = RegistrationNavigationController.withCoordinator(
            coordinator,
            appReadiness: appReadiness
        )
        
        viewController.present(navController, animated: true)
    }
}
