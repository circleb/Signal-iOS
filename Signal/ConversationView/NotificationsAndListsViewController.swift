//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import UserNotifications
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
    private let isPreview: Bool

    private var hasCheckedNotificationPermissions = false

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

    /// Same cache as WebAppsListViewController; used to show bulletin button only when app is in cache and to open with bookmarks.
    private lazy var webAppsService: WebAppsServiceProtocol = {
        let cache = WebAppsStoreImpl(keyValueStore: KeyValueStore(collection: "WebApps"))
        return WebAppsService(
            networkManager: SSKEnvironment.shared.networkManagerRef,
            cache: cache,
            databaseStorage: SSKEnvironment.shared.databaseStorageRef
        )
    }()

    override init() {
        self.directusService = DirectusSubscriptionService()
        self.userInfoStore = SSOUserInfoStoreImpl()
        self.nonSignalStore = NonSignalNotificationStore(keyValueStore: KeyValueStore(collection: "NonSignalNotifications"))
        self.isPreview = false
        super.init()
    }

    init(
        directusService: DirectusSubscriptionServiceProtocol,
        userInfoStore: SSOUserInfoStore,
        nonSignalStore: NonSignalNotificationStore,
        isPreview: Bool = false
    ) {
        self.directusService = directusService
        self.userInfoStore = userInfoStore
        self.nonSignalStore = nonSignalStore
        self.isPreview = isPreview
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        manageButton.configuration = UIButton.Configuration.plain()
        manageButton.addTarget(self, action: #selector(toggleSubscriptionsVisibility), for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeButtonTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: manageButton)
        updateNavigationForCurrentMode()
        loadData()
    }

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadNotifications()
        ensureWebAppsCacheForBulletinButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isPreview || hasCheckedNotificationPermissions {
            return
        }
        hasCheckedNotificationPermissions = true

        Task { @MainActor in
            await checkAndRequestNotificationPermissionsIfNeeded()
        }
    }

    /// If bulletin web app isn't in cache (e.g. user opened notifications before Web Apps tab), fetch from API so the "View full bulletin" button can appear.
    private func ensureWebAppsCacheForBulletinButton() {
        // Prefer lookup by stable Directus id, but fall back to legacy entry-based lookup for compatibility.
        if webAppsService.getCachedWebApp(byId: Self.bulletinWebAppId) != nil ||
            webAppsService.getCachedWebApp(byEntry: Self.bulletinEntry) != nil {
            return
        }
        Task {
            _ = try? await webAppsService.fetchWebApps().awaitable()
            await MainActor.run { [weak self] in
                self?.updateTableContents()
            }
        }
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
        guard !isPreview else {
            // In preview mode we rely on debug helpers to seed notifications.
            updateTableContents()
            return
        }
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

    private func updateNavigationForCurrentMode() {
        var config = manageButton.configuration ?? UIButton.Configuration.plain()
        config.title = nil
        config.baseForegroundColor = .label
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)

        let (symbolName, titleKey, titleComment): (String, String, String) = {
            if areSubscriptionsVisible {
                return (
                    "bell.badge",
                    "NOTIFICATIONS_LISTS_TITLE_SUBSCRIPTIONS",
                    "Title for the subscriptions management view in the notifications sheet."
                )
            } else {
                return (
                    "gear.badge",
                    "NOTIFICATIONS_LISTS_TITLE_NOTIFICATIONS",
                    "Title for the notifications list in the notifications sheet."
                )
            }
        }()

        config.image = UIImage(systemName: symbolName)

        UIView.performWithoutAnimation {
            manageButton.configuration = config
            manageButton.layoutIfNeeded()
        }

        navigationItem.title = OWSLocalizedString(titleKey, comment: titleComment)
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
        let descriptionText = OWSLocalizedString(
            "NOTIFICATIONS_LISTS_SUBSCRIPTIONS_DESCRIPTION",
            comment: "Descriptive text shown above the list of notification subscriptions."
        )
        section.headerAttributedTitle = NSAttributedString(
            string: descriptionText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
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
                    cell.tintColor = .secondaryLabel
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

    /// Bulletin web app from Directus (prefer id, fall back to entry for compatibility).
    private static let bulletinWebAppId = "a648ffbc-5ada-45be-bd53-46ae0135a55e"
    private static let bulletinEntry = "my.homesteadheritage.org/bulletin"

    private func buildNotificationsSection() -> OWSTableSection {
        let section = OWSTableSection()
        if notifications.isEmpty {
            let emptyText = OWSLocalizedString("NOTIFICATIONS_LISTS_NO_NOTIFICATIONS", comment: "Empty state when there are no non-Signal notifications.")
            section.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.accessoryType = .none
                cell.selectionStyle = .none
                let label = UILabel()
                label.text = emptyText
                label.font = .preferredFont(forTextStyle: .body)
                label.textColor = .secondaryLabel
                label.textAlignment = .center
                label.numberOfLines = 0
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(label)
                let padding: CGFloat = 64
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                    label.leadingAnchor.constraint(greaterThanOrEqualTo: cell.contentView.leadingAnchor, constant: 20),
                    cell.contentView.trailingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 20),
                    label.topAnchor.constraint(greaterThanOrEqualTo: cell.contentView.topAnchor, constant: padding),
                    cell.contentView.bottomAnchor.constraint(greaterThanOrEqualTo: label.bottomAnchor, constant: padding)
                ])
                return cell
            }))
        } else {
        for notif in notifications {
            let notifCopy = notif
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                    OWSTableItem.configureCell(cell)

                    let dateLabel = UILabel()
                    dateLabel.font = .systemFont(ofSize: 12, weight: .medium)
                    dateLabel.textColor = .secondaryLabel
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "MMM d"
                    dateLabel.text = dateFormatter.string(from: notifCopy.date)

                    let datePill = UIView()
                    datePill.backgroundColor = .secondarySystemBackground
                    datePill.layer.cornerRadius = 12
                    datePill.addSubview(dateLabel)
                    dateLabel.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        dateLabel.topAnchor.constraint(equalTo: datePill.topAnchor, constant: 4),
                        dateLabel.bottomAnchor.constraint(equalTo: datePill.bottomAnchor, constant: -4),
                        dateLabel.leadingAnchor.constraint(equalTo: datePill.leadingAnchor, constant: 8),
                        dateLabel.trailingAnchor.constraint(equalTo: datePill.trailingAnchor, constant: -8)
                    ])
                    cell.contentView.addSubview(datePill)
                    datePill.translatesAutoresizingMaskIntoConstraints = false

                    let titleLabel = UILabel()
                    titleLabel.font = .boldSystemFont(ofSize: 20)
                    titleLabel.textColor = .label
                    titleLabel.numberOfLines = 1
                    titleLabel.lineBreakMode = .byTruncatingTail
                    titleLabel.text = notifCopy.title

                    let bodyLabel = UILabel()
                    bodyLabel.font = .systemFont(ofSize: 15)
                    bodyLabel.textColor = .secondaryLabel
                    bodyLabel.numberOfLines = 2
                    bodyLabel.lineBreakMode = .byTruncatingTail
                    bodyLabel.text = notifCopy.body

                    let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
                    stack.axis = .vertical
                    stack.spacing = 4

                    cell.contentView.addSubview(stack)

                    let dotLeadingAnchor: NSLayoutXAxisAnchor
                    if notifCopy.isRead {
                        dotLeadingAnchor = cell.contentView.leadingAnchor
                    } else {
                        let dot = UIView()
                        dot.backgroundColor = .systemBlue
                        dot.layer.cornerRadius = 5
                        dot.translatesAutoresizingMaskIntoConstraints = false
                        cell.contentView.addSubview(dot)
                        NSLayoutConstraint.activate([
                            dot.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 20),
                            dot.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                            dot.widthAnchor.constraint(equalToConstant: 10),
                            dot.heightAnchor.constraint(equalToConstant: 10)
                        ])
                        dotLeadingAnchor = dot.trailingAnchor
                    }

                    stack.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        datePill.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                        datePill.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -20),
                        stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 20),
                        stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -20),
                        stack.leadingAnchor.constraint(equalTo: dotLeadingAnchor, constant: notifCopy.isRead ? 20 : 12),
                        stack.trailingAnchor.constraint(lessThanOrEqualTo: datePill.leadingAnchor, constant: -8)
                    ])
                    return cell
                },
                actionBlock: { [weak self] in
                    self?.didSelectNotification(notifCopy)
                }
            ))
        }
        }
        let bulletinApp = webAppsService.getCachedWebApp(byId: Self.bulletinWebAppId)
            ?? webAppsService.getCachedWebApp(byEntry: Self.bulletinEntry)
        // Button only when bulletin web app is in cache. Opens same as WebAppsListViewController (bookmarks, etc.).
        if bulletinApp != nil {
            let openBulletinTitle = OWSLocalizedString("NOTIFICATIONS_LISTS_OPEN_BULLETIN", comment: "Button to open the full bulletin in the web app.")
            section.add(OWSTableItem.disclosureItem(withText: openBulletinTitle) { [weak self] in
                guard let self,
                      let webApp = self.webAppsService.getCachedWebApp(byId: Self.bulletinWebAppId)
                        ?? self.webAppsService.getCachedWebApp(byEntry: Self.bulletinEntry) else { return }
                let webVC = WebAppWebViewController(webApp: webApp, webAppsService: self.webAppsService, userInfoStore: self.userInfoStore)
                self.navigationController?.pushViewController(webVC, animated: true)
            })
        }
        return section
    }

    @MainActor
    private func checkAndRequestNotificationPermissionsIfNeeded() async {
        let pushManager = AppEnvironment.shared.pushRegistrationManagerRef

        let needsAuth = await pushManager.needsNotificationAuthorization()
        if needsAuth {
            await pushManager.registerUserNotificationSettings()
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return
        case .denied:
            await presentNotificationsDisabledAlertIfNeeded()
        case .notDetermined:
            // If we're here, something went wrong with needsNotificationAuthorization; avoid looping.
            return
        case .ephemeral:
            return
        @unknown default:
            return
        }
    }

    @MainActor
    private func presentNotificationsDisabledAlertIfNeeded() async {
        let title = OWSLocalizedString(
            "NOTIFICATIONS_LISTS_SYSTEM_NOTIFICATIONS_DISABLED_TITLE",
            comment: "Title for an alert shown from the notifications sheet when system notifications are disabled for Signal."
        )
        let message = OWSLocalizedString(
            "NOTIFICATIONS_LISTS_SYSTEM_NOTIFICATIONS_DISABLED_MESSAGE",
            comment: "Message for an alert shown from the notifications sheet explaining that iOS notifications are disabled for Signal."
        )
        let openSettingsTitle = OWSLocalizedString(
            "NOTIFICATIONS_LISTS_OPEN_SETTINGS_BUTTON",
            comment: "Button label to open the iOS Settings app from the notifications sheet."
        )

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: CommonStrings.okButton,
                style: .cancel
            )
        )
        alert.addAction(
            UIAlertAction(
                title: openSettingsTitle,
                style: .default,
                handler: { _ in
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            )
        )

        present(alert, animated: true)
    }

    @objc
    private func toggleSubscriptionsVisibility() {
        areSubscriptionsVisible.toggle()
        updateNavigationForCurrentMode()
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

    /// Swipe right (leading): Mark as read (only for unread).
    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let notificationsSectionIndex = areSubscriptionsVisible ? Section.notifications.rawValue : Section.subscriptions.rawValue
        guard indexPath.section == notificationsSectionIndex,
              indexPath.row < notifications.count else { return nil }
        let notif = notifications[indexPath.row]
        guard !notif.isRead else { return nil }
        let action = ContextualActionBuilder.makeContextualAction(
            style: .normal,
            color: UIColor.Signal.ultramarine,
            image: "checkmark.circle.fill",
            title: CommonStrings.readAction
        ) { [weak self] completion in
            self?.markNotificationAsRead(identifier: notif.identifier)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    /// Swipe left (trailing): Delete notification.
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let notificationsSectionIndex = areSubscriptionsVisible ? Section.notifications.rawValue : Section.subscriptions.rawValue
        guard indexPath.section == notificationsSectionIndex,
              indexPath.row < notifications.count else { return nil }
        let notif = notifications[indexPath.row]
        let action = ContextualActionBuilder.makeContextualAction(
            style: .destructive,
            color: UIColor.Signal.red,
            image: "trash-fill",
            title: CommonStrings.deleteButton
        ) { [weak self] completion in
            self?.deleteNotification(identifier: notif.identifier)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        let notificationsSectionIndex = areSubscriptionsVisible ? Section.notifications.rawValue : Section.subscriptions.rawValue
        guard indexPath.section == notificationsSectionIndex,
              let cell = tableView.cellForRow(at: indexPath) else { return }

        // Match the visual style of inset sections by rounding the swipe container.
        let radius: CGFloat = 24
        if let container = cell.superview {
            container.layer.cornerRadius = radius
            container.layer.masksToBounds = true
            container.clipsToBounds = true
        } else {
            cell.layer.cornerRadius = radius
            cell.layer.masksToBounds = true
            cell.clipsToBounds = true
        }
    }

    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        guard let indexPath,
              let cell = tableView.cellForRow(at: indexPath) else { return }
        if let container = cell.superview {
            container.layer.cornerRadius = 0
            container.layer.masksToBounds = false
            container.clipsToBounds = false
        } else {
            cell.layer.cornerRadius = 0
            cell.layer.masksToBounds = false
            cell.clipsToBounds = false
        }
    }

    private func markNotificationAsRead(identifier: String) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            nonSignalStore.markAsRead(identifier: identifier, transaction: tx)
        }
        reloadNotifications()
        NotificationCenter.default.post(name: .nonSignalNotificationsDidChange, object: nil)
    }

    private func deleteNotification(identifier: String) {
        if !isPreview {
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                nonSignalStore.remove(identifier: identifier, transaction: tx)
            }
        } else {
            notifications.removeAll { $0.identifier == identifier }
        }
        reloadNotifications()
        NotificationCenter.default.post(name: .nonSignalNotificationsDidChange, object: nil)
    }
}

#if DEBUG && canImport(SwiftUI)
import SwiftUI

// MARK: - Debug preview mocks

private final class MockDirectusSubscriptionService: DirectusSubscriptionServiceProtocol {
    func getSubscriptions() async throws -> [DirectusSubscription] {
        let json = """
        {
          "data": [
            {
              "id": "1",
              "sort": 1,
              "label": "Critical updates",
              "slug": "critical-updates",
              "is_default": true,
              "description": "Security alerts and important account notices."
            },
            {
              "id": "2",
              "sort": 2,
              "label": "Product news",
              "slug": "product-news",
              "is_default": false,
              "description": "New features and product announcements."
            },
            {
              "id": "3",
              "sort": 3,
              "label": "Tips & tricks",
              "slug": "tips-tricks",
              "is_default": false,
              "description": "Occasional tips to get more out of Signal."
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(DirectusSubscriptionResponse.self, from: data)
        return decoded.data
    }

    func getEnrolledDevicesByEmail(_ email: String) async throws -> [DirectusHcpEnrolledDevice] {
        // Not needed for preview; return empty.
        return []
    }

    func getDeviceSubscriptionPivotsByEmail(_ email: String) async throws -> [DirectusMemberSubscriptionPivot] {
        let json = """
        {
          "data": [
            {
              "id": "pivot-1",
              "hcp_enrolled_devices_id": "device-1",
              "Subscriptions_id": "1"
            },
            {
              "id": "pivot-2",
              "hcp_enrolled_devices_id": "device-1",
              "Subscriptions_id": "2"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(DirectusMemberSubscriptionPivotResponse.self, from: data)
        return decoded.data.pivots
    }

    func createDeviceSubscriptionPivot(deviceId: String, subscriptionId: String) async throws -> DirectusMemberSubscriptionPivot {
        // No-op implementation for preview.
        let json = """
        {
          "data": [
            {
              "id": "pivot-\\(deviceId)-\\(subscriptionId)",
              "hcp_enrolled_devices_id": "\\(deviceId)",
              "Subscriptions_id": "\\(subscriptionId)"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(DirectusMemberSubscriptionPivotResponse.self, from: data)
        return decoded.data.pivots[0]
    }

    func deleteDeviceSubscriptionPivot(pivotId: String) async throws {
        // No-op for preview.
    }

    func saveUserSubscriptions(email: String, selectedSubscriptionIds: Set<String>) async throws {
        // No-op for preview; we don't persist anything.
    }
}

private final class MockSSOUserInfoStore: SSOUserInfoStore {
    private let userInfo: SSOUserInfo

    init() {
        self.userInfo = SSOUserInfo(
            phoneNumber: "+1 555-0100",
            email: "hcp@example.com",
            name: "Example HCP",
            sub: "preview-sub",
            accessToken: "preview-access-token",
            refreshToken: nil,
            roles: ["hcp"],
            groups: [],
            realmAccess: nil,
            resourceAccess: nil
        )
    }

    func storeUserInfo(_ userInfo: SSOUserInfo) {}

    func getUserInfo() -> SSOUserInfo? {
        return userInfo
    }

    func clearUserInfo() {}

    func getUserRoles() -> [String] {
        return userInfo.roles
    }

    func getUserGroups() -> [String] {
        return userInfo.groups
    }

    func hasRole(_ role: String) -> Bool {
        return userInfo.roles.contains(role)
    }

    func hasGroup(_ group: String) -> Bool {
        return userInfo.groups.contains(group)
    }

    func hasAnyRole(_ roles: [String]) -> Bool {
        return roles.contains { userInfo.roles.contains($0) }
    }

    func hasAnyGroup(_ groups: [String]) -> Bool {
        return groups.contains { userInfo.groups.contains($0) }
    }
}

// MARK: - Debug helpers for notifications

extension NotificationsAndListsViewController {
    func _debugLoadSampleNotifications() {
        notifications = [
            StoredNonSignalNotification(
                identifier: "notif-1",
                title: "Heritage Life Conference",
                body: "There’s a new clinical bulletin about medication safety. Tap to read more.",
                date: Date(),
                isRead: false,
                actionURL: "https://cms.homesteadheritage.org/items/Bulletin/93"
            ),
            StoredNonSignalNotification(
                identifier: "notif-2",
                title: "New bulletin available",
                body: "There’s a new clinical bulletin about medication safety. Tap to read more.",
                date: Date().addingTimeInterval(-263600),
                isRead: false,
                actionURL: "https://cms.homesteadheritage.org/items/Bulletin/93"
            ),
            StoredNonSignalNotification(
                identifier: "notif-3",
                title: "System maintenance window",
                body: "Directus will undergo scheduled maintenance tonight from 2–3 AM.",
                date: Date().addingTimeInterval(-963600),
                isRead: true,
                actionURL: "https://cms.homesteadheritage.org/items/Bulletin/93"
            )
        ]
    }
}

// MARK: - SwiftUI preview

private struct NotificationsAndListsViewControllerPreview: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let mockDirectus = MockDirectusSubscriptionService()
        let mockUserInfoStore = MockSSOUserInfoStore()
        let nonSignalStore = NonSignalNotificationStore(
            keyValueStore: KeyValueStore(collection: "MockNonSignalNotifications")
        )

        let viewController = NotificationsAndListsViewController(
            directusService: mockDirectus,
            userInfoStore: mockUserInfoStore,
            nonSignalStore: nonSignalStore,
            isPreview: true
        )

        viewController._debugLoadSampleNotifications()

        let navController = OWSNavigationController(rootViewController: viewController)
        return navController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No-op
    }
}

struct NotificationsAndListsViewController_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsAndListsViewControllerPreview()
            .ignoresSafeArea()
    }
}
#endif
