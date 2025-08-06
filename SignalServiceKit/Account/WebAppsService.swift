//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol WebAppsServiceProtocol {
    func fetchWebApps() -> Promise<[WebApp]>
    func getCachedWebApps() -> [WebApp]?
    func cacheWebApps(_ apps: [WebApp]) async
    func clearCache() async
    func getWebAppsByCategory() -> [WebAppCategory]
    func searchWebApps(query: String) -> [WebApp]
    func getWebAppsByLocation(_ location: String) -> [WebApp]
}

public class WebAppsService: WebAppsServiceProtocol {
    private let networkManager: NetworkManager
    private let cache: WebAppsStore
    private let databaseStorage: SDSDatabaseStorage

    public init(networkManager: NetworkManager, cache: WebAppsStore, databaseStorage: SDSDatabaseStorage) {
        self.networkManager = networkManager
        self.cache = cache
        self.databaseStorage = databaseStorage
    }

    public func fetchWebApps() -> Promise<[WebApp]> {
        return Promise.wrapAsync {
            guard let url = URL(string: WebAppsConfig.apiEndpoint) else {
                throw WebAppsError.invalidURL
            }

            // Use direct URLSession for external URLs instead of TSRequest/NetworkManager
            let session = OWSURLSession(
                securityPolicy: OWSURLSession.defaultSecurityPolicy,
                configuration: OWSURLSession.defaultConfigurationWithoutCaching,
                canUseSignalProxy: false
            )
            
            var headers = HttpHeaders()
            headers.addDefaultHeaders()
            
            let response = try await session.performRequest(
                url.absoluteString,
                method: .get,
                headers: headers
            )
            
            guard let data = response.responseBodyData,
                  let webApps = try? JSONDecoder().decode([WebApp].self, from: data) else {
                throw WebAppsError.invalidResponse
            }

            await self.databaseStorage.awaitableWrite { tx in
                self.cache.storeWebApps(webApps, tx: tx)
            }
            return webApps
        }
    }

    public func getCachedWebApps() -> [WebApp]? {
        return databaseStorage.read { tx in
            return cache.getWebApps(tx: tx)
        }
    }

    public func cacheWebApps(_ apps: [WebApp]) async {
        await databaseStorage.awaitableWrite { tx in
            cache.storeWebApps(apps, tx: tx)
        }
    }

    public func clearCache() async {
        await databaseStorage.awaitableWrite { tx in
            cache.clearWebApps(tx: tx)
        }
    }

    public func getWebAppsByCategory() -> [WebAppCategory] {
        let apps = getCachedWebApps() ?? []
        let grouped = Dictionary(grouping: apps) { $0.category }

        return grouped.map { category, apps in
            WebAppCategory(
                name: category,
                apps: apps.sorted { $0.name < $1.name },
                icon: WebAppsConfig.categoryIcons[category] ?? "app.fill"
            )
        }.sorted { $0.name < $1.name }
    }

    public func searchWebApps(query: String) -> [WebApp] {
        let apps = getCachedWebApps() ?? []
        let lowercasedQuery = query.lowercased()

        return apps.filter { app in
            app.name.lowercased().contains(lowercasedQuery) ||
            app.description.lowercased().contains(lowercasedQuery) ||
            app.category.lowercased().contains(lowercasedQuery)
        }
    }

    public func getWebAppsByLocation(_ location: String) -> [WebApp] {
        let apps = getCachedWebApps() ?? []
        return apps.filter { $0.location.contains(location) }
    }
} 
