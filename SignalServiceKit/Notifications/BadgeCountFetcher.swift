//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct BadgeCount {
    public let unreadChatCount: UInt
    public let unreadCallsCount: UInt
    /// Unread count from non-Signal (e.g. HCP/Directus) notifications stored for the in-app list.
    public let unreadNonSignalNotificationsCount: UInt

    public var unreadTotalCount: UInt {
        unreadChatCount + unreadCallsCount + unreadNonSignalNotificationsCount
    }
}

public protocol BadgeCountFetcher {
    func fetchBadgeCount(tx: DBReadTransaction) -> BadgeCount
}

class BadgeCountFetcherImpl: BadgeCountFetcher {
    private static let nonSignalStore = NonSignalNotificationStore(keyValueStore: KeyValueStore(collection: "NonSignalNotifications"))

    public func fetchBadgeCount(tx: DBReadTransaction) -> BadgeCount {
        let unreadInteractionCount = InteractionFinder.unreadCountInAllThreads(transaction: tx)
        let unreadMissedCallCount = DependenciesBridge.shared.callRecordMissedCallManager.countUnreadMissedCalls(tx: tx)
        let nonSignalList = Self.nonSignalStore.fetchAll(transaction: tx)
        let unreadNonSignalCount = UInt(nonSignalList.filter { !$0.isRead }.count)

        return BadgeCount(
            unreadChatCount: unreadInteractionCount,
            unreadCallsCount: unreadMissedCallCount,
            unreadNonSignalNotificationsCount: unreadNonSignalCount
        )
    }
}
