//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol WebAppsStore {
    func storeWebApps(_ apps: [WebApp], tx: DBWriteTransaction)
    func getWebApps(tx: DBReadTransaction) -> [WebApp]?
    func clearWebApps(tx: DBWriteTransaction)
    func getLastFetchDate(tx: DBReadTransaction) -> Date?
    func isCacheExpired(tx: DBReadTransaction) -> Bool
    func getWebApp(by entry: String, tx: DBReadTransaction) -> WebApp?
    func getWebAppsByType(_ type: String, tx: DBReadTransaction) -> [WebApp]
}

public class WebAppsStoreImpl: WebAppsStore {
    private let keyValueStore: KeyValueStore

    public init(keyValueStore: KeyValueStore) {
        self.keyValueStore = keyValueStore
    }

    public func storeWebApps(_ apps: [WebApp], tx: DBWriteTransaction) {
        if let data = try? JSONEncoder().encode(apps) {
            keyValueStore.setData(data, key: WebAppsConfig.cacheKey, transaction: tx)
            keyValueStore.setDate(Date(), key: "\(WebAppsConfig.cacheKey)_last_fetch", transaction: tx)
        }
    }

    public func getWebApps(tx: DBReadTransaction) -> [WebApp]? {
        guard let data = keyValueStore.getData(WebAppsConfig.cacheKey, transaction: tx),
              let apps = try? JSONDecoder().decode([WebApp].self, from: data) else {
            return nil
        }
        return apps
    }

    public func clearWebApps(tx: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: WebAppsConfig.cacheKey, transaction: tx)
        keyValueStore.removeValue(forKey: "\(WebAppsConfig.cacheKey)_last_fetch", transaction: tx)
    }

    public func getLastFetchDate(tx: DBReadTransaction) -> Date? {
        return keyValueStore.getDate("\(WebAppsConfig.cacheKey)_last_fetch", transaction: tx)
    }

    public func isCacheExpired(tx: DBReadTransaction) -> Bool {
        guard let lastFetch = getLastFetchDate(tx: tx) else { return true }
        return Date().timeIntervalSince(lastFetch) > WebAppsConfig.cacheExpirationInterval
    }

    public func getWebApp(by entry: String, tx: DBReadTransaction) -> WebApp? {
        return getWebApps(tx: tx)?.first { $0.entry == entry }
    }

    public func getWebAppsByType(_ type: String, tx: DBReadTransaction) -> [WebApp] {
        return getWebApps(tx: tx)?.filter { $0.type == type } ?? []
    }
} 
