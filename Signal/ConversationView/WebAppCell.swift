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
        selectionStyle = .none

        // Icon
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = Theme.primaryTextColor

        // Labels
        nameLabel.font = .dynamicTypeTitle2
        nameLabel.textColor = Theme.primaryTextColor

        descriptionLabel.font = .dynamicTypeBody
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.numberOfLines = 3

        categoryLabel.font = .dynamicTypeCaption1
        categoryLabel.textColor = .ows_accentBlue

        // Layout
        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(descriptionLabel)

        iconImageView.autoSetDimensions(to: CGSize(width: 40, height: 40))
        iconImageView.autoPinEdge(toSuperviewEdge: .leading, withInset: 24)
        iconImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 16)

        nameLabel.autoPinEdge(.leading, to: .trailing, of: iconImageView, withOffset: 12)
        nameLabel.autoPinEdge(.top, to: .top, of: iconImageView)
        nameLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

        descriptionLabel.autoPinEdge(.leading, to: .leading, of: nameLabel)
        descriptionLabel.autoPinEdge(.top, to: .bottom, of: nameLabel, withOffset: 4)
        descriptionLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)
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
    }
} 

#if DEBUG
import SwiftUI

struct WebAppCell_Previews: PreviewProvider {
    static var previews: some View {
        WebAppCellTablePreview()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("WebAppCell in UITableView")
    }

    private struct WebAppCellTablePreview: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> UIViewController {
            let tableViewController = UITableViewController(style: .insetGrouped)
            tableViewController.tableView.register(WebAppCell.self, forCellReuseIdentifier: "WebAppCell")
            tableViewController.tableView.dataSource = context.coordinator
            tableViewController.tableView.delegate = context.coordinator
            tableViewController.tableView.rowHeight = UITableView.automaticDimension
            tableViewController.tableView.estimatedRowHeight = 80
            return tableViewController
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
            // No dynamic updates needed for static preview data.
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
            private let webApps: [WebApp] = [
                WebApp(
                    entry: "https://example.com/index.html",
                    name: "Sample Web App",
                    description: "Short description.",
                    icon: "text.pad.header",
                    image: "bluegradient.jpg",
                    category: "Category",
                    urlsPermitted: ["https://example.com/*"],
                    location: ["preview"],
                    type: "preview",
                    parent: "preview-parent",
                    id: "preview-1",
                    kcRole: nil
                ),
                WebApp(
                    entry: "https://example.com/long.html",
                    name: "Very Long Web App Name That Wraps Nicely",
                    description: "This is a longer description for the web app that should wrap onto a second line when there is enough text to do so, demonstrating the two-line behavior in the cell within a real UITableView environment.",
                    icon: "birthday.cake.fill",
                    image: "bluegradient.jpg",
                    category: "Category",
                    urlsPermitted: ["https://example.com/*"],
                    location: ["preview"],
                    type: "preview",
                    parent: "preview-parent",
                    id: "preview-2",
                    kcRole: nil
                )
            ]

            func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
                webApps.count
            }

            func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
                guard let cell = tableView.dequeueReusableCell(withIdentifier: "WebAppCell", for: indexPath) as? WebAppCell else {
                    return UITableViewCell(style: .default, reuseIdentifier: nil)
                }
                cell.configure(with: webApps[indexPath.row])
                return cell
            }
        }
    }
}
#endif
