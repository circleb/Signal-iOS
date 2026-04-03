//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit
import PureLayout

class PinnedURLCell: UITableViewCell {
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let urlLabel = UILabel()
    private let webAppLabel = UILabel()
    private let accessCountLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = Theme.backgroundColor
        selectionStyle = .none

        // Icon
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = Theme.primaryTextColor
        iconImageView.autoSetDimensions(to: CGSize(width: 32, height: 32))

        // Labels
        titleLabel.font = .dynamicTypeBody
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.numberOfLines = 1

        urlLabel.font = .dynamicTypeCaption1
        urlLabel.textColor = Theme.secondaryTextAndIconColor
        urlLabel.numberOfLines = 1

        webAppLabel.font = .dynamicTypeCaption2
        webAppLabel.textColor = .ows_accentBlue

        accessCountLabel.font = .dynamicTypeCaption2
        accessCountLabel.textColor = Theme.secondaryTextAndIconColor

        // Layout
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(urlLabel)
        contentView.addSubview(webAppLabel)
        contentView.addSubview(accessCountLabel)

        iconImageView.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
        iconImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 12)

        titleLabel.autoPinEdge(.leading, to: .trailing, of: iconImageView, withOffset: 12)
        titleLabel.autoPinEdge(.top, to: .top, of: iconImageView)
        titleLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

        urlLabel.autoPinEdge(.leading, to: .leading, of: titleLabel)
        urlLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 2)
        urlLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

        webAppLabel.autoPinEdge(.leading, to: .leading, of: titleLabel)
        webAppLabel.autoPinEdge(.top, to: .bottom, of: urlLabel, withOffset: 4)
        webAppLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 12)

        accessCountLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)
        accessCountLabel.autoPinEdge(.top, to: .top, of: webAppLabel)
    }

    func configure(with pinnedURL: PinnedURL) {
        titleLabel.text = pinnedURL.title
        urlLabel.text = pinnedURL.url
        webAppLabel.text = pinnedURL.webAppName
        accessCountLabel.text = "\(pinnedURL.accessCount) visits"

        // Set icon
        if let icon = pinnedURL.icon, let image = UIImage(systemName: icon) {
            iconImageView.image = image
        } else {
            iconImageView.image = UIImage(systemName: "link")
        }
    }
}
