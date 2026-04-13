//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

enum SSOStrings {

    static var signInWithHeritageSSO: String {
        OWSLocalizedString(
            "SSO_SIGN_IN_WITH_HERITAGE",
            comment: "Button label to sign in using Heritage SSO during onboarding.",
        )
    }

    static var registerWithHCP: String {
        OWSLocalizedString(
            "SSO_REGISTER_WITH_HCP",
            comment: "Button label to open HCP registration in a web view.",
        )
    }

    static var configureChat: String {
        OWSLocalizedString(
            "SSO_CONFIGURE_CHAT",
            comment: "Button label to continue and configure a new chat account after SSO.",
        )
    }

    static var transferChatsFromSignal: String {
        OWSLocalizedString(
            "SSO_TRANSFER_CHATS_FROM_SIGNAL",
            comment: "Button label to transfer an existing Signal account after SSO.",
        )
    }

    static var retry: String {
        OWSLocalizedString(
            "SSO_RETRY",
            comment: "Button label to retry the SSO sign-in flow after an error.",
        )
    }

    static var retrySSOLogin: String {
        OWSLocalizedString(
            "SSO_RETRY_SSO_LOGIN",
            comment: "Button label to retry SSO login from the authentication screen.",
        )
    }
}
