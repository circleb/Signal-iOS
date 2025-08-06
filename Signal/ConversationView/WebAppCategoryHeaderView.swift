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
    private let iconImageView = UIImageView()

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

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .ows_accentBlue

        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)

        iconImageView.autoSetDimensions(to: CGSize(width: 20, height: 20))
        iconImageView.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
        iconImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 12)

        titleLabel.autoPinEdge(.leading, to: .trailing, of: iconImageView, withOffset: 8)
        titleLabel.autoPinEdge(.top, to: .top, of: iconImageView)
        titleLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)
        titleLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
    }

    func configure(with category: WebAppCategory) {
        titleLabel.text = category.name

        if let icon = UIImage(systemName: category.icon) {
            iconImageView.image = icon
        } else {
            iconImageView.image = UIImage(systemName: "folder.fill")
        }
    }
} 