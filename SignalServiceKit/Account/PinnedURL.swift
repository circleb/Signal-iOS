//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct PinnedURL: Codable, Equatable {
    public let id: String                    // Unique identifier
    public let webAppEntry: String           // Associated webapp entry
    public let webAppName: String            // Webapp name for display
    public let title: String                 // User-defined title
    public let url: String                   // The Bookmark
    public let icon: String?                 // Optional custom icon (SF Symbol)
    public let createdAt: Date               // Creation timestamp
    public let lastAccessed: Date?           // Last access timestamp
    public let accessCount: Int              // Number of times accessed

    public init(
        id: String = UUID().uuidString,
        webAppEntry: String,
        webAppName: String,
        title: String,
        url: String,
        icon: String? = nil,
        createdAt: Date = Date(),
        lastAccessed: Date? = nil,
        accessCount: Int = 0
    ) {
        self.id = id
        self.webAppEntry = webAppEntry
        self.webAppName = webAppName
        self.title = title
        self.url = url
        self.icon = icon
        self.createdAt = createdAt
        self.lastAccessed = lastAccessed
        self.accessCount = accessCount
    }
}
