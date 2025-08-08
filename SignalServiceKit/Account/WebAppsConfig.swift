//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct WebAppsConfig {
    static let apiEndpoint = "https://my.homesteadheritage.org/api/v2/webapps.php"
    static let globalAllowEndpoint = "https://my.homesteadheritage.org/api/v2/globalallow.php"
    static let cacheKey = "web_apps_cache"
    static let globalAllowCacheKey = "global_allow_cache"
    static let cacheExpirationInterval: TimeInterval = 3600 // 1 hour

    // Web app categories
    static let defaultCategories = [
        "Community Updates",
        "Communication",
        "Resources",
        "Tools"
    ]

    // Default icons for categories
    public static let categoryIcons = [
        "Community Updates": "newspaper.fill",
        "Communication": "message.fill",
        "Resources": "folder.fill",
        "Tools": "wrench.and.screwdriver.fill"
    ]
} 
