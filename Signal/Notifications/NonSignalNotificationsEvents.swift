//
// Copyright 2026
//

import Foundation

extension Notification.Name {
    /// Posted whenever the NonSignalNotificationStore is modified (append/mark-as-read) so
    /// UI components (like the portal bell icon) can update unread state and badges.
    static let nonSignalNotificationsDidChange = Notification.Name("nonSignalNotificationsDidChange")
}

