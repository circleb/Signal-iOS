//
// Copyright 2026
// SPDX-License-Identifier: AGPL-3.0-only
//

public import UIKit

/// Optional hook for host apps (e.g. HCP + Firebase) to observe view-controller appearance without linking analytics into SignalUI.
public enum ViewAppearanceAnalytics {
    public static var onViewControllerDidAppear: ((UIViewController) -> Void)?

    public static func notifyViewControllerDidAppear(_ viewController: UIViewController) {
        onViewControllerDidAppear?(viewController)
    }
}
