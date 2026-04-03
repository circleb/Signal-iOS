//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PinnedURLsStore {
    func storePinnedURL(_ pinnedURL: PinnedURL, tx: DBWriteTransaction)
    func removePinnedURL(_ id: String, tx: DBWriteTransaction)
    func updatePinnedURL(_ pinnedURL: PinnedURL, tx: DBWriteTransaction)
    func getPinnedURLs(tx: DBReadTransaction) -> [PinnedURL]
    func getPinnedURLs(for webAppEntry: String, tx: DBReadTransaction) -> [PinnedURL]
    func getPinnedURL(by id: String, tx: DBReadTransaction) -> PinnedURL?
    func clearAllPinnedURLs(tx: DBWriteTransaction)
    func incrementAccessCount(for id: String, tx: DBWriteTransaction)
}
