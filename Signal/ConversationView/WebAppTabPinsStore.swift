//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension Notification.Name {
    /// Posted when the ordered list of web apps pinned to the home tab bar changes.
    static let webAppTabPinsDidChange = Notification.Name("webAppTabPinsDidChange")
}

/// Persists which web apps (by API UUID) appear as dedicated tabs on the home tab bar.
final class WebAppTabPinsStore {

    static let shared = WebAppTabPinsStore()

    /// Default pins for first launch (never written before).
    /// Uses `entry` strings from `webapps.php` when the API does not provide `id`.
    static let defaultOrderedPinIds: [String] = [
        "19fb63a7-6900-4574-b963-4566404ac4cf",
        "2d9a7b8a-757c-4d8e-8bb3-99ce43956782",
    ]

    /// Maximum number of web apps that may be pinned (excluding fixed Portal + Chats tabs).
    static let maxPinnedWebApps = 5

    private static let orderedIdsKey = "orderedPinnedWebAppIds"
    private static let userModifiedKey = "webAppTabPinsUserModified"

    private let keyValueStore = KeyValueStore(collection: "WebAppTabPins")
    private let databaseStorage: SDSDatabaseStorage

    init(databaseStorage: SDSDatabaseStorage = SSKEnvironment.shared.databaseStorageRef) {
        self.databaseStorage = databaseStorage
    }

    /// Ensures default pins are written once when the key has never been set.
    func ensureDefaultPinsIfNeeded() {
        databaseStorage.write { tx in
            let userModified = keyValueStore.getBool(Self.userModifiedKey, transaction: tx) ?? false
            let hasPinsKey = keyValueStore.hasValue(Self.orderedIdsKey, transaction: tx)
            let pins = keyValueStore.getStringArray(Self.orderedIdsKey, transaction: tx) ?? []
            if userModified { return }
            if !hasPinsKey {
                keyValueStore.setStringArray(Self.defaultOrderedPinIds, key: Self.orderedIdsKey, transaction: tx)
                return
            }
            // Key exists but list is empty (e.g. invalid UUID pins pruned against API with no `id` field).
            if pins.isEmpty {
                keyValueStore.setStringArray(Self.defaultOrderedPinIds, key: Self.orderedIdsKey, transaction: tx)
            }
        }
    }

    func orderedPinIds() -> [String] {
        databaseStorage.read { tx in
            keyValueStore.getStringArray(Self.orderedIdsKey, transaction: tx) ?? []
        }
    }

    func setOrderedPinIds(_ ids: [String]) {
        databaseStorage.write { tx in
            keyValueStore.setBool(true, key: Self.userModifiedKey, transaction: tx)
            keyValueStore.setStringArray(ids, key: Self.orderedIdsKey, transaction: tx)
        }
        NotificationCenter.default.postOnMainThread(name: .webAppTabPinsDidChange, object: nil)
    }

    /// Updates stored order without posting `.webAppTabPinsDidChange` (e.g. pruning missing apps during tab rebuild).
    func replaceOrderedPinIdsSilently(_ ids: [String]) {
        databaseStorage.write { tx in
            keyValueStore.setStringArray(ids, key: Self.orderedIdsKey, transaction: tx)
        }
    }

    func isPinned(webAppId: String) -> Bool {
        orderedPinIds().contains(webAppId)
    }

    @discardableResult
    func addPin(webAppId: String) -> Bool {
        var ids = orderedPinIds()
        guard !ids.contains(webAppId) else { return true }
        guard ids.count < Self.maxPinnedWebApps else { return false }
        ids.append(webAppId)
        setOrderedPinIds(ids)
        return true
    }

    func removePin(webAppId: String) {
        var ids = orderedPinIds()
        ids.removeAll { $0 == webAppId }
        setOrderedPinIds(ids)
    }
}

