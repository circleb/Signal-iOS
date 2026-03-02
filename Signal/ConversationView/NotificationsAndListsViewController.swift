//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit

/// Sheet: manage subscription lists (Directus) and view/mark-as-read received non-Signal notifications.
final class NotificationsAndListsViewController: OWSTableViewController2 {

    enum Section: Int, CaseIterable {
        case subscriptions = 0
        case notifications = 1
    }

    private let directusService: DirectusSubscriptionServiceProtocol
    private let userInfoStore: SSOUserInfoStore
    private let nonSignalStore: NonSignalNotificationStore

    private var subscriptions: [DirectusSubscription] = []
    private var selectedSubscriptionIds: Set<String> = []
    private var notifications: [StoredNonSignalNotification] = []
    private var isLoadingSubscriptions = false
    private var isSavingSubscriptions = false
    private var subscriptionsError: String?
    private var areSubscriptionsVisible = false
    private let manageButton = UIButton(type: .system)

    private static let subscriptionCellReuse = "SubscriptionCell"
    private static let notificationCellReuse = "NotificationCell"

    override init() {
        self.directusService = DirectusSubscriptionService()
        self.userInfoStore = SSOUserInfoStoreImpl()
        self.nonSignalStore = NonSignalNotificationStore(keyValueStore: KeyValueStore(collection: "NonSignalNotifications"))
        super.init()
    }

    init(
        directusService: DirectusSubscriptionServiceProtocol,
        userInfoStore: SSOUserInfoStore,
        nonSignalStore: NonSignalNotificationStore
    ) {
        self.directusService = directusService
        self.userInfoStore = userInfoStore
        self.nonSignalStore = nonSignalStore
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        var config = UIButton.Configuration.filled()
        config.title = OWSLocalizedString(
            "NOTIFICATIONS_LISTS_MANAGE_BUTTON",
            comment: "Button title to show the notification list subscriptions."
        )
        config.baseBackgroundColor = UIColor.Signal.ultramarine
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        manageButton.configuration = config
        manageButton.addTarget(self, action: #selector(toggleSubscriptionsVisibility), for: .touchUpInside)
        navigationItem.titleView = manageButton
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadNotifications()
    }

    private func loadData() {
        loadSubscriptions()
        reloadNotifications()
    }

    private func loadSubscriptions() {
        guard let email = userInfoStore.getUserInfo()?.email, !email.isEmpty else {
            subscriptions = []
            selectedSubscriptionIds = []
            subscriptionsError = nil
            updateTableContents()
            return
        }
        isLoadingSubscriptions = true
        subscriptionsError = nil
        updateTableContents()
        Task { @MainActor in
            do {
                let subs = try await directusService.getSubscriptions()
                let pivots = (try? await directusService.getDeviceSubscriptionPivotsByEmail(email)) ?? []
                var selected = Set(pivots.map(\.subscriptionsId))
                if selected.isEmpty {
                    selected = Set(subs.filter { $0.isDefault == true }.map(\.id))
                }
                self.subscriptions = subs
                self.selectedSubscriptionIds = selected
                self.subscriptionsError = nil
            } catch {
                if let directusError = error as? DirectusSubscriptionError, case .notConfigured = directusError {
                    self.subscriptionsError = OWSLocalizedString("NOTIFICATIONS_LISTS_DIRECTUS_NOT_CONFIGURED", comment: "Shown when the notification list service is not configured for this build.")
                } else {
                    self.subscriptionsError = error.localizedDescription
                }
            }
            self.isLoadingSubscriptions = false
            self.updateTableContents()
        }
    }

    private func reloadNotifications() {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            self.notifications = self.nonSignalStore.fetchAll(transaction: tx)
        }
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        if areSubscriptionsVisible {
            contents.add(buildSubscriptionsSection())
        } else {
            contents.add(buildNotificationsSection())
        }
        self.contents = contents
    }

    private func buildSubscriptionsSection() -> OWSTableSection {
        let section = OWSTableSection()
        guard let email = userInfoStore.getUserInfo()?.email, !email.isEmpty else {
            section.add(OWSTableItem.label(withText: OWSLocalizedString("NOTIFICATIONS_LISTS_SIGN_IN_PROMPT", comment: "Prompt to sign in to manage subscriptions.")))
            return section
        }
        if isLoadingSubscriptions {
            section.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.textLabel?.text = OWSLocalizedString("NOTIFICATIONS_LISTS_LOADING", comment: "Loading indicator for subscriptions.")
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
                return cell
            }))
            return section
        }
        if let error = subscriptionsError {
            section.add(OWSTableItem.label(withText: error))
            return section
        }
        for sub in subscriptions {
            let isSelected = selectedSubscriptionIds.contains(sub.id)
            let isDefault = sub.isDefault ?? false
            section.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.textLabel?.text = sub.label
                cell.detailTextLabel?.text = sub.description
                cell.accessoryType = isSelected ? .checkmark : .none
                cell.selectionStyle = isDefault ? .none : .default
                if isDefault {
                    cell.contentView.alpha = 0.5
                }
                return cell
            }, actionBlock: { [weak self] in
                guard let self, !isDefault else { return }
                if selectedSubscriptionIds.contains(sub.id) {
                    selectedSubscriptionIds.remove(sub.id)
                } else {
                    selectedSubscriptionIds.insert(sub.id)
                }
                updateTableContents()
                saveSubscriptions()
            }))
        }
        return section
    }

    private func saveSubscriptions() {
        guard let email = userInfoStore.getUserInfo()?.email, !email.isEmpty else { return }
        if isSavingSubscriptions { return }
        isSavingSubscriptions = true
        updateTableContents()
        Task { @MainActor in
            do {
                try await directusService.saveUserSubscriptions(email: email, selectedSubscriptionIds: selectedSubscriptionIds)
                isSavingSubscriptions = false
                updateTableContents()
            } catch {
                isSavingSubscriptions = false
                updateTableContents()
                let alert = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: CommonStrings.okButton, style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func buildNotificationsSection() -> OWSTableSection {
        let section = OWSTableSection()
        if notifications.isEmpty {
            section.add(OWSTableItem.label(withText: OWSLocalizedString("NOTIFICATIONS_LISTS_NO_NOTIFICATIONS", comment: "Empty state when there are no non-Signal notifications.")))
            return section
        }
        for notif in notifications {
            let notifCopy = notif
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
                    OWSTableItem.configureCell(cell)
                    cell.textLabel?.text = notifCopy.title
                    cell.detailTextLabel?.text = notifCopy.body
                    cell.textLabel?.numberOfLines = 1
                    cell.detailTextLabel?.numberOfLines = 0
                    cell.accessoryView = notifCopy.isRead ? nil : {
                        let dot = UIView()
                        dot.backgroundColor = .systemBlue
                        dot.layer.cornerRadius = 4
                        dot.frame = CGRect(x: 0, y: 0, width: 8, height: 8)
                        return dot
                    }()
                    return cell
                },
                actionBlock: { [weak self] in
                    self?.didSelectNotification(notifCopy)
                }
            ))
        }
        return section
    }

    @objc
    private func toggleSubscriptionsVisibility() {
        areSubscriptionsVisible.toggle()
        var config = manageButton.configuration ?? UIButton.Configuration.filled()
        config.title = OWSLocalizedString(
            areSubscriptionsVisible ? "NOTIFICATIONS_LISTS_SHOW_NOTIFICATIONS_BUTTON" : "NOTIFICATIONS_LISTS_MANAGE_BUTTON",
            comment: "Button title to toggle between showing notification list subscriptions and received notifications."
        )
        manageButton.configuration = config
        updateTableContents()
    }

    private func didSelectNotification(_ notification: StoredNonSignalNotification) {
        if !notification.isRead {
            markNotificationAsRead(identifier: notification.identifier)
        }

        guard let urlString = notification.actionURL, let url = URL(string: urlString) else {
            return
        }

        // If this looks like a Bulletin JSON endpoint, render the HTML body via BulletinViewController.
        if urlString.contains("/items/Bulletin/") {
            let vc = BulletinViewController(bulletinURL: url, title: notification.title)
            navigationController?.pushViewController(vc, animated: true)
            return
        }

        // Fallback: open generic URLs in the system browser.
        UIApplication.shared.open(url)
    }
}

// MARK: - Swipe actions for notifications

extension NotificationsAndListsViewController {

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let notificationsSectionIndex = areSubscriptionsVisible ? Section.notifications.rawValue : Section.subscriptions.rawValue
        guard indexPath.section == notificationsSectionIndex,
              indexPath.row < notifications.count else { return nil }
        let notif = notifications[indexPath.row]
        guard !notif.isRead else { return nil }
        let action = ContextualActionBuilder.makeContextualAction(
            style: .normal,
            color: UIColor.Signal.ultramarine,
            image: "chat-check-fill",
            title: CommonStrings.readAction
        ) { [weak self] completion in
            self?.markNotificationAsRead(identifier: notif.identifier)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func markNotificationAsRead(identifier: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            nonSignalStore.markAsRead(identifier: identifier, transaction: tx)
        }
        reloadNotifications()
    }
}
