//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class AppIconBadgeUpdater {
    private let badgeManager: BadgeManager
    private var nonSignalNotificationsObserver: NSObjectProtocol?

    init(badgeManager: BadgeManager) {
        self.badgeManager = badgeManager
    }

    func startObserving() {
        badgeManager.addObserver(self)
        nonSignalNotificationsObserver = NotificationCenter.default.addObserver(
            forName: .nonSignalNotificationsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.badgeManager.invalidateBadgeValue()
        }
    }

    deinit {
        if let nonSignalNotificationsObserver {
            NotificationCenter.default.removeObserver(nonSignalNotificationsObserver)
        }
    }
}

extension AppIconBadgeUpdater: BadgeObserver {
    func didUpdateBadgeCount(_ badgeManager: BadgeManager, badgeCount: BadgeCount) {
        UIApplication.shared.applicationIconBadgeNumber = Int(badgeCount.unreadTotalCount)
    }
}
