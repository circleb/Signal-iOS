//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import PureLayout

class PinnedURLSectionHeaderView: UITableViewHeaderFooterView {
    private let titleLabel = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.backgroundColor = Theme.backgroundColor

        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textColor = Theme.primaryTextColor

        contentView.addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
    }

    func configure(with title: String) {
        titleLabel.text = title
    }
}
