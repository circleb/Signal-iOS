//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct WebApp: Codable {
    public let entry: String           // Domain/URL for the web app
    public let name: String           // Display name
    public let description: String    // App description
    public let icon: String          // SF Symbol name
    public let image: String         // Background image filename
    public let category: String      // Category for grouping
    public let urlsPermitted: [String] // Allowed URL patterns
    public let location: [String]    // Where to show the app
    public let type: String          // App type (sublist, rss, etc.)
    public let parent: String        // Parent app reference
    public let kcRole: String?       // Required Keycloak role for access
    
    public init(entry: String, name: String, description: String, icon: String, image: String, category: String, urlsPermitted: [String], location: [String], type: String, parent: String, kcRole: String? = nil) {
        self.entry = entry
        self.name = name
        self.description = description
        self.icon = icon
        self.image = image
        self.category = category
        self.urlsPermitted = urlsPermitted
        self.location = location
        self.type = type
        self.parent = parent
        self.kcRole = kcRole
    }
}

public struct WebAppCategory: Codable {
    public let name: String
    public let apps: [WebApp]
    public let icon: String
    
    public init(name: String, apps: [WebApp], icon: String) {
        self.name = name
        self.apps = apps
        self.icon = icon
    }
}

public struct GlobalAllowEntry: Codable {
    public let entry: String
    public let name: String
    
    public init(entry: String, name: String) {
        self.entry = entry
        self.name = name
    }
} 