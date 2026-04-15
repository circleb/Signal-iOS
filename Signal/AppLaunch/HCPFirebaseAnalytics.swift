//
// Copyright 2026
// SPDX-License-Identifier: AGPL-3.0-only
//

import FirebaseAnalytics
import UIKit

enum HCPFirebaseAnalytics {
    static func logScreenView(for viewController: UIViewController) {
        let name = String(describing: type(of: viewController))
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: name,
        ])
    }

    /// Logged when a portal `WKWebView` commits to a new document URL (deduped by caller).
    static func logWebDocumentURL(webAppName: String, url: String) {
        Analytics.logEvent("hcp_web_app_url", parameters: [
            "web_app_name": webAppName,
            "url": url,
        ])
    }

    /// SSO web flows use the same event with a `flow` parameter for segmentation in GA4.
    static func logSSOWebDocumentURL(url: String) {
        Analytics.logEvent("hcp_web_app_url", parameters: [
            "flow": "sso",
            "url": url,
        ])
    }
}
