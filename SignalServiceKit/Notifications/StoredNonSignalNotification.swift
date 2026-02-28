//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A non-Signal (e.g. HCP/Directus) push notification stored locally for the notifications list.
public struct StoredNonSignalNotification: Codable, Equatable {
    public let identifier: String
    public let title: String
    public let body: String
    public let date: Date
    public var isRead: Bool
    public let actionURL: String?

    public init(identifier: String, title: String, body: String, date: Date, isRead: Bool = false, actionURL: String? = nil) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.date = date
        self.isRead = isRead
        self.actionURL = actionURL
    }
}
