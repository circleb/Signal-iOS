//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class PinnedURLsStoreImpl: PinnedURLsStore {
    private let keyValueStore: KeyValueStore

    public init(keyValueStore: KeyValueStore) {
        self.keyValueStore = keyValueStore
    }

    public func storePinnedURL(_ pinnedURL: PinnedURL, tx: DBWriteTransaction) {
        var existingURLs = getPinnedURLs(tx: tx)
        existingURLs.append(pinnedURL)
        savePinnedURLs(existingURLs, tx: tx)
    }

    public func removePinnedURL(_ id: String, tx: DBWriteTransaction) {
        var existingURLs = getPinnedURLs(tx: tx)
        existingURLs.removeAll { $0.id == id }
        savePinnedURLs(existingURLs, tx: tx)
    }

    public func updatePinnedURL(_ pinnedURL: PinnedURL, tx: DBWriteTransaction) {
        var existingURLs = getPinnedURLs(tx: tx)
        if let index = existingURLs.firstIndex(where: { $0.id == pinnedURL.id }) {
            existingURLs[index] = pinnedURL
            savePinnedURLs(existingURLs, tx: tx)
        }
    }

    public func getPinnedURLs(tx: DBReadTransaction) -> [PinnedURL] {
        guard let data = keyValueStore.getData("pinned_urls", transaction: tx),
              let pinnedURLs = try? JSONDecoder().decode([PinnedURL].self, from: data) else {
            return []
        }
        return pinnedURLs
    }

    public func getPinnedURLs(for webAppEntry: String, tx: DBReadTransaction) -> [PinnedURL] {
        return getPinnedURLs(tx: tx).filter { $0.webAppEntry == webAppEntry }
    }

    public func getPinnedURL(by id: String, tx: DBReadTransaction) -> PinnedURL? {
        return getPinnedURLs(tx: tx).first { $0.id == id }
    }

    public func clearAllPinnedURLs(tx: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: "pinned_urls", transaction: tx)
    }

    public func incrementAccessCount(for id: String, tx: DBWriteTransaction) {
        var existingURLs = getPinnedURLs(tx: tx)
        if let index = existingURLs.firstIndex(where: { $0.id == id }) {
            existingURLs[index] = PinnedURL(
                id: existingURLs[index].id,
                webAppEntry: existingURLs[index].webAppEntry,
                webAppName: existingURLs[index].webAppName,
                title: existingURLs[index].title,
                url: existingURLs[index].url,
                icon: existingURLs[index].icon,
                createdAt: existingURLs[index].createdAt,
                lastAccessed: Date(),
                accessCount: existingURLs[index].accessCount + 1
            )
            savePinnedURLs(existingURLs, tx: tx)
        }
    }

    private func savePinnedURLs(_ pinnedURLs: [PinnedURL], tx: DBWriteTransaction) {
        if let data = try? JSONEncoder().encode(pinnedURLs) {
            keyValueStore.setData(data, key: "pinned_urls", transaction: tx)
        }
    }
}
