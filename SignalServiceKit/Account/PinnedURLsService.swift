//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PinnedURLsServiceProtocol {
    func pinURL(_ url: String, title: String, webApp: WebApp, icon: String?) async throws
    func unpinURL(_ id: String) async throws
    func updatePinnedURL(_ pinnedURL: PinnedURL) async throws
    func getPinnedURLs() -> [PinnedURL]
    func getPinnedURLs(for webApp: WebApp) -> [PinnedURL]
    func getPinnedURL(by id: String) -> PinnedURL?
    func recordAccess(for id: String) async
    func clearAllPinnedURLs() async throws
    func getPinnedURLsByWebApp() -> [String: [PinnedURL]]
    func searchPinnedURLs(query: String) -> [PinnedURL]
}

public class PinnedURLsService: PinnedURLsServiceProtocol {
    private let store: PinnedURLsStore
    private let databaseStorage: SDSDatabaseStorage

    public init(store: PinnedURLsStore, databaseStorage: SDSDatabaseStorage) {
        self.store = store
        self.databaseStorage = databaseStorage
    }

    public func pinURL(_ url: String, title: String, webApp: WebApp, icon: String?) async throws {
        let pinnedURL = PinnedURL(
            webAppEntry: webApp.entry,
            webAppName: webApp.name,
            title: title,
            url: url,
            icon: icon
        )

        await databaseStorage.awaitableWrite { tx in
            self.store.storePinnedURL(pinnedURL, tx: tx)
        }
    }

    public func unpinURL(_ id: String) async throws {
        await databaseStorage.awaitableWrite { tx in
            self.store.removePinnedURL(id, tx: tx)
        }
    }

    public func updatePinnedURL(_ pinnedURL: PinnedURL) async throws {
        await databaseStorage.awaitableWrite { tx in
            self.store.updatePinnedURL(pinnedURL, tx: tx)
        }
    }

    public func getPinnedURLs() -> [PinnedURL] {
        return databaseStorage.read { tx in
            return store.getPinnedURLs(tx: tx)
        }
    }

    public func getPinnedURLs(for webApp: WebApp) -> [PinnedURL] {
        return databaseStorage.read { tx in
            return store.getPinnedURLs(for: webApp.entry, tx: tx)
        }
    }

    public func getPinnedURL(by id: String) -> PinnedURL? {
        return databaseStorage.read { tx in
            return store.getPinnedURL(by: id, tx: tx)
        }
    }

    public func recordAccess(for id: String) async {
        await databaseStorage.awaitableWrite { tx in
            self.store.incrementAccessCount(for: id, tx: tx)
        }
    }

    public func clearAllPinnedURLs() async throws {
        await databaseStorage.awaitableWrite { tx in
            self.store.clearAllPinnedURLs(tx: tx)
        }
    }

    public func getPinnedURLsByWebApp() -> [String: [PinnedURL]] {
        let allPinnedURLs = getPinnedURLs()
        return Dictionary(grouping: allPinnedURLs) { $0.webAppEntry }
    }

    public func searchPinnedURLs(query: String) -> [PinnedURL] {
        let allPinnedURLs = getPinnedURLs()
        let lowercasedQuery = query.lowercased()

        return allPinnedURLs.filter { pinnedURL in
            pinnedURL.title.lowercased().contains(lowercasedQuery) ||
            pinnedURL.webAppName.lowercased().contains(lowercasedQuery) ||
            pinnedURL.url.lowercased().contains(lowercasedQuery)
        }
    }
}
