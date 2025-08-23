//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit
import PureLayout

class WebAppCell: UITableViewCell {
    private let iconImageView = UIImageView()
    private let nameLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let categoryLabel = UILabel()
    private let backgroundImageView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        setupThemeObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        // Background image
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.layer.cornerRadius = 12
        backgroundImageView.alpha = 0.1

        // Icon
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = Theme.primaryTextColor

        // Labels
        nameLabel.font = .dynamicTypeTitle2
        nameLabel.textColor = Theme.primaryTextColor

        descriptionLabel.font = .dynamicTypeBody
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        descriptionLabel.numberOfLines = 2

        categoryLabel.font = .dynamicTypeCaption1
        categoryLabel.textColor = .ows_accentBlue

        // Layout
        contentView.addSubview(backgroundImageView)
        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(descriptionLabel)

        backgroundImageView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))

        iconImageView.autoSetDimensions(to: CGSize(width: 40, height: 40))
        iconImageView.autoPinEdge(toSuperviewEdge: .leading, withInset: 24)
        iconImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 16)

        nameLabel.autoPinEdge(.leading, to: .trailing, of: iconImageView, withOffset: 12)
        nameLabel.autoPinEdge(.top, to: .top, of: iconImageView)
        nameLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

        descriptionLabel.autoPinEdge(.leading, to: .leading, of: nameLabel)
        descriptionLabel.autoPinEdge(.top, to: .bottom, of: nameLabel, withOffset: 4)
        descriptionLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 16)
    }

    private func setupThemeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
        )
    }

    @objc
    private func themeDidChange() {
        applyTheme()
    }

    private func applyTheme() {
        iconImageView.tintColor = Theme.primaryTextColor
        nameLabel.textColor = Theme.primaryTextColor
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        categoryLabel.textColor = .ows_accentBlue
    }

    func configure(with webApp: WebApp) {
        nameLabel.text = webApp.name
        descriptionLabel.text = webApp.description
        categoryLabel.text = webApp.category

        // Set icon
        if let icon = UIImage(systemName: webApp.icon) {
            iconImageView.image = icon
        } else {
            iconImageView.image = UIImage(systemName: "app.fill")
        }

        // Set background image if available
        if !webApp.image.isEmpty {
            // Load background image from bundle or network
            // For now, use a gradient based on the image name
            backgroundImageView.backgroundColor = gradientColor(for: webApp.image)
        }
    }

    private func gradientColor(for imageName: String) -> UIColor {
        // Create gradient colors based on image name
        switch imageName {
        case "bluegradient.jpg":
            return UIColor.systemBlue.withAlphaComponent(0.1)
        case "neutralgradient.jpg":
            return UIColor.systemGray.withAlphaComponent(0.1)
        default:
            return UIColor.systemBlue.withAlphaComponent(0.1)
        }
    }
} 