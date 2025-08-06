//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import PureLayout

class EmptyStateView: UIView {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let retryButton = UIButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = Theme.backgroundColor

        imageView.image = UIImage(systemName: "globe")
        imageView.tintColor = Theme.secondaryTextAndIconColor
        imageView.contentMode = .scaleAspectFit

        titleLabel.text = "No Web Apps Available"
        titleLabel.font = .dynamicTypeTitle2
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        messageLabel.text = "Check your internet connection and try again."
        messageLabel.font = .dynamicTypeBody
        messageLabel.textColor = Theme.secondaryTextAndIconColor
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        retryButton.setTitle("Retry", for: .normal)
        retryButton.setTitleColor(.ows_accentBlue, for: .normal)
        retryButton.titleLabel?.font = .dynamicTypeBody

        addSubview(imageView)
        addSubview(titleLabel)
        addSubview(messageLabel)
        addSubview(retryButton)

        imageView.autoSetDimensions(to: CGSize(width: 80, height: 80))
        imageView.autoCenterInSuperview()

        titleLabel.autoPinEdge(.top, to: .bottom, of: imageView, withOffset: 16)
        titleLabel.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(hMargin: 32, vMargin: 0))

        messageLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 8)
        messageLabel.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(hMargin: 32, vMargin: 0))

        retryButton.autoPinEdge(.top, to: .bottom, of: messageLabel, withOffset: 24)
        retryButton.autoCenterInSuperview()
    }

    func configure(retryAction: @escaping () -> Void) {
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        self.retryAction = retryAction
    }

    private var retryAction: (() -> Void)?

    @objc private func retryTapped() {
        retryAction?()
    }
} 