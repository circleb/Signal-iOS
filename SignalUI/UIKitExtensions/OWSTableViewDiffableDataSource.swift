//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import UIKit
/// A `UITableViewDiffableDataSource` that exposes hooks into various
/// `UITableViewDataSource` APIs that callers may be interested in.
public class OWSTableViewDiffableDataSource<
    SectionIdentifier: Hashable,
    ItemIdentifier: Hashable,
>: UITableViewDiffableDataSource<
    SectionIdentifier,
    ItemIdentifier,
> {

    public var canMoveRow: ((_ indexPath: IndexPath) -> Bool)?
    public var didMoveRow: ((_ sourceIndexPath: IndexPath, _ destinationIndexPath: IndexPath) -> Void)?

    override public func tableView(
        _ tableView: UITableView,
        canMoveRowAt indexPath: IndexPath,
    ) -> Bool {
        canMoveRow?(indexPath) ?? true
    }

    override public func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath,
    ) {
        didMoveRow?(sourceIndexPath, destinationIndexPath)
    }
}
