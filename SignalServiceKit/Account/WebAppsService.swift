//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol WebAppsServiceProtocol {
    func fetchWebApps() -> Promise<[WebApp]>
    func fetchWebAppsCategorized() -> Promise<[WebAppCategory]>
    func fetchWebAppsCategorized(userRoles: [String]) -> Promise<[WebAppCategory]>
    func fetchGlobalAllowList() -> Promise<[GlobalAllowEntry]>
    func getCachedWebApps() -> [WebApp]?
    func getCachedCategorizedWebApps() -> [WebAppCategory]?
    func getCachedGlobalAllowList() -> [GlobalAllowEntry]?
    func cacheWebApps(_ apps: [WebApp]) async
    func cacheGlobalAllowList(_ entries: [GlobalAllowEntry]) async
    func clearCache() async
    func getWebAppsByCategory() -> [WebAppCategory]
    func getWebAppsByCategory(userRoles: [String]) -> [WebAppCategory]
    func searchWebApps(query: String) -> [WebApp]
    func searchWebApps(query: String, userRoles: [String]) -> [WebApp]
    func getWebAppsByLocation(_ location: String) -> [WebApp]
    func getWebAppsByLocation(_ location: String, userRoles: [String]) -> [WebApp]
    func isURLGloballyAllowed(_ url: URL) -> Bool
    func filterWebAppsByRole(_ apps: [WebApp], userRoles: [String]) -> [WebApp]
    func getPinnedURLsService() -> PinnedURLsServiceProtocol
}

public class WebAppsService: WebAppsServiceProtocol {
    private let networkManager: NetworkManager
    private let cache: WebAppsStore
    internal let databaseStorage: SDSDatabaseStorage

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

            // Automatically categorize webapps when fetched
            let categorizedWebApps = self.categorizeWebApps(webApps)
            
            await self.databaseStorage.awaitableWrite { tx in
                self.cache.storeWebApps(webApps, tx: tx)
                // Also store the categorized version
                self.cache.storeCategorizedWebApps(categorizedWebApps, tx: tx)
            }
            return webApps
        }
    }

    /// Fetches webapps and returns them categorized by their categories
    public func fetchWebAppsCategorized() -> Promise<[WebAppCategory]> {
        return Promise.wrapAsync {
            let webApps = try await self.fetchWebApps().awaitable()
            return self.categorizeWebApps(webApps)
        }
    }

    /// Fetches webapps and returns them categorized by their categories, filtered by user roles
    public func fetchWebAppsCategorized(userRoles: [String]) -> Promise<[WebAppCategory]> {
        return Promise.wrapAsync {
            let webApps = try await self.fetchWebApps().awaitable()
            let filteredWebApps = self.filterWebAppsByRole(webApps, userRoles: userRoles)
            return self.categorizeWebApps(filteredWebApps)
        }
    }

    /// Helper method to categorize webapps by their category field
    private func categorizeWebApps(_ webApps: [WebApp]) -> [WebAppCategory] {
        let grouped = Dictionary(grouping: webApps) { $0.category }

        return grouped.map { category, apps in
            WebAppCategory(
                name: category,
                apps: apps.sorted { $0.name < $1.name }
            )
        }.sorted { $0.name < $1.name }
    }

    public func fetchGlobalAllowList() -> Promise<[GlobalAllowEntry]> {
        return Promise.wrapAsync {
            guard let url = URL(string: WebAppsConfig.globalAllowEndpoint) else {
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
                  let globalAllowList = try? JSONDecoder().decode([GlobalAllowEntry].self, from: data) else {
                throw WebAppsError.invalidResponse
            }

            await self.databaseStorage.awaitableWrite { tx in
                self.cache.storeGlobalAllowList(globalAllowList, tx: tx)
            }
            return globalAllowList
        }
    }

    public func getCachedWebApps() -> [WebApp]? {
        return databaseStorage.read { tx in
            return cache.getWebApps(tx: tx)
        }
    }

    public func getCachedCategorizedWebApps() -> [WebAppCategory]? {
        return databaseStorage.read { tx in
            return cache.getCategorizedWebApps(tx: tx)
        }
    }

    public func getCachedGlobalAllowList() -> [GlobalAllowEntry]? {
        return databaseStorage.read { tx in
            return cache.getGlobalAllowList(tx: tx)
        }
    }

    public func cacheWebApps(_ apps: [WebApp]) async {
        await databaseStorage.awaitableWrite { tx in
            cache.storeWebApps(apps, tx: tx)
        }
    }

    public func cacheGlobalAllowList(_ entries: [GlobalAllowEntry]) async {
        await databaseStorage.awaitableWrite { tx in
            cache.storeGlobalAllowList(entries, tx: tx)
        }
    }

    public func clearCache() async {
        await databaseStorage.awaitableWrite { tx in
            cache.clearWebApps(tx: tx)
            cache.clearCategorizedWebApps(tx: tx)
            cache.clearGlobalAllowList(tx: tx)
        }
    }

    public func getWebAppsByCategory() -> [WebAppCategory] {
        // First try to get cached categorized webapps
        if let cachedCategories = getCachedCategorizedWebApps() {
            return cachedCategories
        }
        
        // Fallback to categorizing from individual webapps
        let apps = getCachedWebApps() ?? []
        return categorizeWebApps(apps)
    }

    public func getWebAppsByCategory(userRoles: [String]) -> [WebAppCategory] {
        // First try to get cached categorized webapps and filter by role
        if let cachedCategories = getCachedCategorizedWebApps() {
            return cachedCategories.map { category in
                let filteredApps = filterWebAppsByRole(category.apps, userRoles: userRoles)
                return WebAppCategory(
                    name: category.name,
                    apps: filteredApps.sorted { $0.name < $1.name }
                )
            }.filter { !$0.apps.isEmpty } // Remove empty categories
        }
        
        // Fallback to categorizing from individual webapps
        let apps = getCachedWebApps() ?? []
        let filteredApps = filterWebAppsByRole(apps, userRoles: userRoles)
        return categorizeWebApps(filteredApps)
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

    public func searchWebApps(query: String, userRoles: [String]) -> [WebApp] {
        let apps = getCachedWebApps() ?? []
        let filteredApps = filterWebAppsByRole(apps, userRoles: userRoles)
        let lowercasedQuery = query.lowercased()

        return filteredApps.filter { app in
            app.name.lowercased().contains(lowercasedQuery) ||
            app.description.lowercased().contains(lowercasedQuery) ||
            app.category.lowercased().contains(lowercasedQuery)
        }
    }

    public func getWebAppsByLocation(_ location: String) -> [WebApp] {
        let apps = getCachedWebApps() ?? []
        return apps.filter { $0.location.contains(location) }
    }

    public func getWebAppsByLocation(_ location: String, userRoles: [String]) -> [WebApp] {
        let apps = getCachedWebApps() ?? []
        let filteredApps = filterWebAppsByRole(apps, userRoles: userRoles)
        return filteredApps.filter { $0.location.contains(location) }
    }

    public func isURLGloballyAllowed(_ url: URL) -> Bool {
        let globalAllowList = getCachedGlobalAllowList() ?? []
        let urlString = url.absoluteString.lowercased()
        
        return globalAllowList.contains { entry in
            let entryLower = entry.entry.lowercased()
            return urlString.contains(entryLower)
        }
    }

    public func filterWebAppsByRole(_ apps: [WebApp], userRoles: [String]) -> [WebApp] {
        return apps.filter { app in
            // If no kcRole is specified, the app is accessible to everyone
            guard let requiredRole = app.kcRole else {
                return true
            }
            
            // Check if user has the required role
            return userRoles.contains(requiredRole)
        }
    }
    
    public func getPinnedURLsService() -> PinnedURLsServiceProtocol {
        // Create a new KeyValueStore instance for Bookmarks
        let pinnedURLsKeyValueStore = KeyValueStore(collection: "PinnedURLs")
        return PinnedURLsService(
            store: PinnedURLsStoreImpl(keyValueStore: pinnedURLsKeyValueStore),
            databaseStorage: databaseStorage
        )
    }
} 
