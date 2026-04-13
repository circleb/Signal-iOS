//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import UIKit
public protocol ReusableTableViewCell {
    static var reuseIdentifier: String { get }
}

public extension UITableView {
    /// A typed wrapper around `dequeueReusableCell(withIdentifier:)`.
    ///
    /// - Parameters:
    ///   - type: The `UITableViewCell` subclass that should be dequeued.
    /// - Returns:
    ///     A typed `UITableViewCell` subclass, or `nil` if the type's `reuseIdentifier` is not registered.
    func dequeueReusableCell<T: ReusableTableViewCell & UITableViewCell>(_: T.Type) -> T? {
        let untypedCell = dequeueReusableCell(withIdentifier: T.reuseIdentifier)
        guard let typedCell = untypedCell as? T else {
            owsFailDebug("Registered cells should exist and have the correct type.")
            return nil
        }
        return typedCell
    }

    /// A typed wrapper around `register(_:forCellReuseIdentifier:)` for cell
    /// subclasses that conform to the `ReusableTableViewCell` protocol.
    func register<T: ReusableTableViewCell & UITableViewCell>(_: T.Type) {
        register(T.self, forCellReuseIdentifier: T.reuseIdentifier)
    }

    /// A typed wrapper around `dequeueReusableCell(withIdentifier:for:)`.
    ///
    /// - Parameters:
    ///   - type: The `UITableViewCell` subclass that should be dequeued.
    ///   - indexPath: An index path for where the cell will be shown.
    /// - Returns:
    ///     A typed `UITableViewCell` subclass.
    func dequeueReusableCell<T: ReusableTableViewCell & UITableViewCell>(_: T.Type, for indexPath: IndexPath) -> T {
        dequeueReusableCell(withIdentifier: T.reuseIdentifier, for: indexPath) as! T
    }
}
