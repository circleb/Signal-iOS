//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit
import PureLayout

class WebAppCategoryHeaderView: UITableViewHeaderFooterView {
    private let titleLabel = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundView = UIView()
        backgroundView?.backgroundColor = Theme.backgroundColor

        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textColor = Theme.primaryTextColor

        contentView.addSubview(titleLabel)

        titleLabel.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
        titleLabel.autoPinEdge(toSuperviewEdge: .top, withInset: 12)
        titleLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)
        titleLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
    }
} 
