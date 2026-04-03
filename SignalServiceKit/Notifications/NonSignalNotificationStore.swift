//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private let storageKey = "non_signal_notifications"
private let maxStoredCount = 500

public final class NonSignalNotificationStore {

    private let keyValueStore: KeyValueStore

    public init(keyValueStore: KeyValueStore) {
        self.keyValueStore = keyValueStore
    }

    /// Appends a notification (or updates by identifier) and trims to max count. Newest first after insert.
    public func append(_ notification: StoredNonSignalNotification, transaction: DBWriteTransaction) {
        var list = (try? keyValueStore.getCodableValue(forKey: storageKey, failDebugOnParseError: false, transaction: transaction) as [StoredNonSignalNotification]?) ?? []
        list.removeAll { $0.identifier == notification.identifier }
        list.insert(notification, at: 0)
        if list.count > maxStoredCount {
            list = Array(list.prefix(maxStoredCount))
        }
        try? keyValueStore.setCodable(optional: list, key: storageKey, transaction: transaction)
    }

    /// Returns all stored notifications, newest first.
    public func fetchAll(transaction: DBReadTransaction) -> [StoredNonSignalNotification] {
        (try? keyValueStore.getCodableValue(forKey: storageKey, failDebugOnParseError: false, transaction: transaction) as [StoredNonSignalNotification]?) ?? []
    }

    /// Marks the notification with the given identifier as read.
    public func markAsRead(identifier: String, transaction: DBWriteTransaction) {
        var list = (try? keyValueStore.getCodableValue(forKey: storageKey, failDebugOnParseError: false, transaction: transaction) as [StoredNonSignalNotification]?) ?? []
        guard let idx = list.firstIndex(where: { $0.identifier == identifier }) else { return }
        var item = list[idx]
        item = StoredNonSignalNotification(identifier: item.identifier, title: item.title, body: item.body, date: item.date, isRead: true, actionURL: item.actionURL)
        list[idx] = item
        try? keyValueStore.setCodable(optional: list, key: storageKey, transaction: transaction)
    }

    /// Removes the notification with the given identifier from storage.
    public func remove(identifier: String, transaction: DBWriteTransaction) {
        var list = (try? keyValueStore.getCodableValue(forKey: storageKey, failDebugOnParseError: false, transaction: transaction) as [StoredNonSignalNotification]?) ?? []
        list.removeAll { $0.identifier == identifier }
        try? keyValueStore.setCodable(optional: list, key: storageKey, transaction: transaction)
    }
}
