//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
public import UIKit
import SignalServiceKit
import SignalUI

enum HomeTabKind: Equatable {
    case portal
    case chatList
    case pinnedWebApp(webAppId: String)

    var tabIdentifier: String {
        switch self {
        case .portal:
            return "portal"
        case .chatList:
            return "chats"
        case .pinnedWebApp(let id):
            return "pinned-\(id)"
        }
    }
}

class HomeTabBarController: UITabBarController {

    private let appReadiness: AppReadinessSetter
    private let portalUserInfoStore: SSOUserInfoStore
    private let ssoService: SSOServiceProtocol

    init(appReadiness: AppReadinessSetter) {
        self.appReadiness = appReadiness
        let userStore = SSOUserInfoStoreImpl()
        self.portalUserInfoStore = userStore
        self.ssoService = SSOService(userInfoStore: userStore)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    lazy var chatListViewController = ChatListViewController(chatListMode: .inbox, appReadiness: appReadiness)
    lazy var chatListNavController = OWSNavigationController(rootViewController: chatListViewController)
    private lazy var chatListTabBarItem: UITabBarItem = {
        UITabBarItem(
            title: OWSLocalizedString(
                "CHAT_LIST_TITLE_INBOX",
                comment: "Title for the chat list's default mode.",
            ),
            image: UIImage(imageLiteralResourceName: "tab-chats"),
            selectedImage: UIImage(named: "tab-chats"),
        )
    }()

    lazy var storiesViewController = StoriesViewController(
        appReadiness: appReadiness,
        spoilerState: SpoilerRenderState(),
    )
    lazy var storiesNavController = OWSNavigationController(rootViewController: storiesViewController)

    lazy var callsListViewController = CallsListViewController(appReadiness: appReadiness)
    lazy var callsListNavController = OWSNavigationController(rootViewController: callsListViewController)

    lazy var webAppsService: WebAppsServiceProtocol = {
        let cache = WebAppsStoreImpl(keyValueStore: KeyValueStore(collection: "WebApps"))
        return WebAppsService(networkManager: SSKEnvironment.shared.networkManagerRef, cache: cache, databaseStorage: SSKEnvironment.shared.databaseStorageRef)
    }()

    let webAppTabPinsStore: WebAppTabPinsStore = .shared

    lazy var webAppsListViewController = WebAppsListViewController(
        webAppsService: webAppsService,
        userInfoStore: portalUserInfoStore,
        ssoService: ssoService,
        tabPinsStore: webAppTabPinsStore,
    )
    lazy var webAppsNavController = OWSNavigationController(rootViewController: webAppsListViewController)
    private lazy var webAppsTabBarItem: UITabBarItem = {
        UITabBarItem(
            title: "Portal",
            image: UIImage(systemName: "square.stack"),
            selectedImage: UIImage(systemName: "square.stack.fill"),
        )
    }()

    /// Pinned web app tabs reuse these navigation controllers so state is preserved while pinned.
    private var pinnedNavigationControllers = [String: OWSNavigationController]()

    private var tabKinds: [HomeTabKind] = []

    // UITab (iOS 18 iPad) persistence — see `uiTab(for:)`.
    private var _uiTabs = [String: Any]()

    @available(iOS 18, *)
    func uiTab(for kind: HomeTabKind) -> UITab {
        let identifier = kind.tabIdentifier
        if let existing = _uiTabs[identifier] as? UITab {
            return existing
        }
        let nav = navigationController(for: kind)
        let title = tabTitle(for: kind)
        let image = tabImage(for: kind)
        let uiTab = UITab(title: title, image: image, identifier: identifier) { _ in
            nav
        }
        _uiTabs[identifier] = uiTab
        return uiTab
    }

    var selectedPrimaryTab: HomeTabKind {
        get {
            guard tabKinds.indices.contains(selectedIndex) else { return .portal }
            return tabKinds[selectedIndex]
        }
        set {
            if let idx = tabKinds.firstIndex(of: newValue) {
                selectedIndex = idx
            }
        }
    }

    var primaryNavigationControllerForSelectedTab: OWSNavigationController {
        navigationController(for: selectedPrimaryTab)
    }

    /// `true` when the stories flow is presented modally (there is no stories tab).
    var isStoriesFlowPresentedModally: Bool {
        presentedViewController === storiesNavController
    }

    var owsTabBar: OWSTabBar? {
        return tabBar as? OWSTabBar
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: .OWSApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(webAppTabPinsDidChange), name: .webAppTabPinsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(webAppsPortalDidRefresh), name: .webAppsPortalDidRefresh, object: nil)

        applyTheme()

        webAppTabPinsStore.ensureDefaultPinsIfNeeded()
        rebuildTabs()

        AppEnvironment.shared.badgeManager.addObserver(self)

        setTabBarHidden(false, animated: false)
    }

    @objc
    private func didEnterForeground() {
        rebuildTabs()
    }

    @objc
    private func webAppTabPinsDidChange() {
        rebuildTabs()
    }

    @objc
    private func webAppsPortalDidRefresh() {
        rebuildTabs()
    }

    @objc
    private func applyTheme() {
        tabBar.tintColor = Theme.primaryTextColor
    }

    private func cachedWebApp(forPinKey pinKey: String) -> WebApp? {
        webAppsService.getCachedWebApp(byId: pinKey) ?? webAppsService.getCachedWebApp(byEntry: pinKey)
    }

    func rebuildTabs() {
        AssertIsOnMainThread()
        // #region agent log
        CursorAgentDebugNDJSON.log(
            hypothesisId: "H1",
            location: "HomeTabBarController.rebuildTabs:entry",
            message: "rebuildTabs started",
            data: [
                "selectedIndex": "\(selectedIndex)",
                "tabKindsCount": "\(tabKinds.count)",
                "vcCount": "\(viewControllers?.count ?? -1)",
            ],
        )
        // #endregion

        func resolvePins(_ ids: [String]) -> [(String, WebApp)] {
            ids.compactMap { pinKey in
                guard let app = self.cachedWebApp(forPinKey: pinKey) else { return nil }
                return (pinKey, app)
            }
        }

        var pinIds = webAppTabPinsStore.orderedPinIds()
        var resolved = resolvePins(pinIds)
        var resolvedIds = resolved.map(\.0)
        // Avoid clearing stored pin IDs while the web app cache is still empty (first launch before fetch).
        let cacheIsPrimed = !(webAppsService.getCachedWebApps() ?? []).isEmpty
        if resolvedIds != pinIds, cacheIsPrimed {
            webAppTabPinsStore.replaceOrderedPinIdsSilently(resolvedIds)
            // Pruning to [] (e.g. legacy UUID pins vs API without `id`) re-seeds defaults in-session when the user never customized pins.
            webAppTabPinsStore.ensureDefaultPinsIfNeeded()
            pinIds = webAppTabPinsStore.orderedPinIds()
            resolved = resolvePins(pinIds)
            resolvedIds = resolved.map(\.0)
        }

        for id in pinnedNavigationControllers.keys where !resolvedIds.contains(id) {
            pinnedNavigationControllers.removeValue(forKey: id)
        }

        for (id, app) in resolved {
            if pinnedNavigationControllers[id] == nil {
                let webVC = WebAppWebViewController(
                    webApp: app,
                    webAppsService: webAppsService,
                    userInfoStore: portalUserInfoStore,
                    prefersSwitchToPortalOnClose: true
                )
                let nav = OWSNavigationController(rootViewController: webVC)
                pinnedNavigationControllers[id] = nav
            }
            if let nav = pinnedNavigationControllers[id] {
                updatePinnedTabBarItem(nav: nav, webApp: app)
            }
        }

        let kinds: [HomeTabKind] = [.portal] + resolved.map { .pinnedWebApp(webAppId: $0.0) } + [.chatList]

        let previousKind: HomeTabKind = if tabKinds.indices.contains(selectedIndex) {
            tabKinds[selectedIndex]
        } else {
            .portal
        }

        tabKinds = kinds

        // UITabBarController can crash if `selectedIndex` is still the old value while
        // `viewControllers` / `tabs` is replaced with a shorter array (e.g. user on Chats
        // at the last index, then a pinned tab in the middle is removed).
        if !kinds.isEmpty, selectedIndex >= kinds.count {
            selectedIndex = kinds.count - 1
        }
        // #region agent log
        CursorAgentDebugNDJSON.log(
            hypothesisId: "H1",
            location: "HomeTabBarController.rebuildTabs:afterClamp",
            message: "about to assign tabs or viewControllers",
            data: [
                "selectedIndex": "\(selectedIndex)",
                "kindsCount": "\(kinds.count)",
                "previousKind": "\(previousKind)",
            ],
        )
        // #endregion

        if #available(iOS 18, *), UIDevice.current.isIPad {
            let validKeys = Set(kinds.map { $0.tabIdentifier })
            for key in _uiTabs.keys where !validKeys.contains(key) {
                _uiTabs.removeValue(forKey: key)
            }
            // #region agent log
            CursorAgentDebugNDJSON.log(
                hypothesisId: "H3",
                location: "HomeTabBarController.rebuildTabs:beforeTabsAssign",
                message: "iOS18 iPad assigning self.tabs",
                data: [
                    "selectedIndex": "\(selectedIndex)",
                    "kindsCount": "\(kinds.count)",
                ],
            )
            // #endregion
            self.tabs = kinds.map { uiTab(for: $0) }
        } else {
            initializeCustomTabBar(tabKinds: kinds)
        }

        applyTheme()

        if let newIndex = kinds.firstIndex(of: previousKind) {
            selectedIndex = newIndex
        } else if let portalIdx = kinds.firstIndex(of: .portal) {
            selectedIndex = portalIdx
        } else if let chatIdx = kinds.firstIndex(of: .chatList) {
            selectedIndex = chatIdx
        } else {
            selectedIndex = 0
        }
        // #region agent log
        CursorAgentDebugNDJSON.log(
            hypothesisId: "H1",
            location: "HomeTabBarController.rebuildTabs:exit",
            message: "rebuildTabs finished",
            data: [
                "selectedIndex": "\(selectedIndex)",
                "kindsCount": "\(kinds.count)",
                "vcCount": "\(viewControllers?.count ?? -1)",
            ],
        )
        // #endregion
    }

    private func initializeCustomTabBar(tabKinds: [HomeTabKind]) {
        // #region agent log
        CursorAgentDebugNDJSON.log(
            hypothesisId: "H2",
            location: "HomeTabBarController.initializeCustomTabBar:entry",
            message: "replacing tabBar and viewControllers",
            data: [
                "selectedIndex": "\(selectedIndex)",
                "newTabKindsCount": "\(tabKinds.count)",
            ],
        )
        // #endregion
        setValue(OWSTabBar(), forKey: "tabBar")
        viewControllers = tabKinds.map { kind in
            let nav = navigationController(for: kind)
            switch kind {
            case .portal:
                nav.tabBarItem = webAppsTabBarItem
            case .chatList:
                nav.tabBarItem = chatListTabBarItem
            case .pinnedWebApp:
                break
            }
            return nav
        }
    }

    private func navigationController(for kind: HomeTabKind) -> OWSNavigationController {
        switch kind {
        case .portal:
            return webAppsNavController
        case .chatList:
            return chatListNavController
        case .pinnedWebApp(let id):
            guard let nav = pinnedNavigationControllers[id] else {
                owsFailDebug("Missing pinned navigation for \(id)")
                return webAppsNavController
            }
            return nav
        }
    }

    private func tabTitle(for kind: HomeTabKind) -> String {
        switch kind {
        case .portal:
            return "Portal"
        case .chatList:
            return OWSLocalizedString(
                "CHAT_LIST_TITLE_INBOX",
                comment: "Title for the chat list's default mode.",
            )
        case .pinnedWebApp(let id):
            return cachedWebApp(forPinKey: id)?.name ?? " "
        }
    }

    private func tabImage(for kind: HomeTabKind) -> UIImage? {
        switch kind {
        case .portal:
            return UIImage(systemName: "square.stack")
        case .chatList:
            return UIImage(imageLiteralResourceName: "tab-chats")
        case .pinnedWebApp(let id):
            guard let app = cachedWebApp(forPinKey: id) else {
                return UIImage(systemName: "app.fill")
            }
            return UIImage(systemName: app.icon) ?? UIImage(systemName: "app.fill")
        }
    }

    private func updatePinnedTabBarItem(nav: OWSNavigationController, webApp: WebApp) {
        let image = UIImage(systemName: webApp.icon) ?? UIImage(systemName: "app.fill")
        nav.tabBarItem = UITabBarItem(title: webApp.name, image: image, selectedImage: image)
    }

    // MARK: - Hiding the tab bar

    // FIXME: Can this conditionally override UITabBarController.isTabBarHidden on iOS 18?
    private var _isTabBarHidden: Bool = false

    /// Hides or displays the tab bar, resizing the selected view controller to
    /// fill the space remaining.
    func setTabBarHidden(
        _ hidden: Bool,
        animated: Bool = true,
        duration: TimeInterval = 0.15,
        completion: ((Bool) -> Void)? = nil,
    ) {
        defer {
            _isTabBarHidden = hidden
        }

        guard _isTabBarHidden != hidden else {
            tabBar.isHidden = hidden
            owsTabBar?.applyTheme()
            completion?(true)
            return
        }

        let oldFrame = self.tabBar.frame
        let containerHeight = tabBar.superview?.bounds.height ?? 0
        let newMinY = hidden ? containerHeight : containerHeight - oldFrame.height
        let additionalSafeArea = hidden
            ? (-oldFrame.height + view.safeAreaInsets.bottom)
            : (oldFrame.height - view.safeAreaInsets.bottom)

        let animations = {
            self.tabBar.frame = self.tabBar.frame.offsetBy(dx: 0, dy: newMinY - oldFrame.y)
            if let vc = self.selectedViewController {
                var additionalSafeAreaInsets = vc.additionalSafeAreaInsets
                additionalSafeAreaInsets.bottom += additionalSafeArea
                vc.additionalSafeAreaInsets = additionalSafeAreaInsets
            }

            self.view.setNeedsDisplay()
            self.view.layoutIfNeeded()
        }

        if animated {
            // Unhide for animations.
            self.tabBar.isHidden = false
            let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
                animations()
            }
            animator.addCompletion({
                self.tabBar.isHidden = hidden
                self.owsTabBar?.applyTheme()
                completion?($0 == .end)
            })
            animator.startAnimation()
        } else {
            animations()
            self.tabBar.isHidden = hidden
            owsTabBar?.applyTheme()
            completion?(true)
        }
    }
}

extension HomeTabBarController: BadgeObserver {
    func didUpdateBadgeCount(_ badgeManager: BadgeManager, badgeCount: BadgeCount) {
        func stringify(_ badgeValue: UInt) -> String? {
            return badgeValue > 0 ? badgeValue.formatted() : nil
        }

        let value = stringify(badgeCount.unreadChatCount)
        chatListTabBarItem.badgeValue = value
        if #available(iOS 18, *), UIDevice.current.isIPad {
            uiTab(for: .chatList).badgeValue = value
        }
    }
}

extension HomeTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if selectedViewController == viewController {
            switch selectedPrimaryTab {
            case .chatList:
                let tableView = chatListViewController.tableView
                tableView.setContentOffset(CGPoint(x: 0, y: -tableView.safeAreaInsets.top), animated: true)
            case .portal:
                let tableView = webAppsListViewController.tableView
                tableView.setContentOffset(CGPoint(x: 0, y: -tableView.safeAreaInsets.top), animated: true)
            case .pinnedWebApp:
                if let webVC = (viewController as? OWSNavigationController)?.viewControllers.first as? WebAppWebViewController {
                    webVC.scrollWebContentToTop(animated: true)
                }
            }
        }

        return true
    }
}

public class OWSTabBar: UITabBar {

    public var fullWidth: CGFloat {
        return superview?.frame.width ?? .zero
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static let backgroundBlurMutingFactor: CGFloat = 0.5
    var blurEffectView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil,
        )
    }

    override public var isHidden: Bool {
        didSet {
            if !isHidden {
                applyTheme()
            }
        }
    }

    // MARK: Theme

    var tabBarBackgroundColor: UIColor {
        Theme.navbarBackgroundColor
    }

    fileprivate func applyTheme() {
        guard !self.isHidden else {
            return
        }

        if #available(iOS 26, *) {
            return
        }

        if UIAccessibility.isReduceTransparencyEnabled {
            blurEffectView?.isHidden = true
            self.backgroundImage = UIImage.image(color: tabBarBackgroundColor)
        } else {
            let blurEffect = Theme.barBlurEffect

            let blurEffectView: UIVisualEffectView = {
                if let existingBlurEffectView = self.blurEffectView {
                    existingBlurEffectView.isHidden = false
                    return existingBlurEffectView
                }

                let blurEffectView = UIVisualEffectView()
                blurEffectView.isUserInteractionEnabled = false

                self.blurEffectView = blurEffectView
                self.insertSubview(blurEffectView, at: 0)
                blurEffectView.autoPinEdgesToSuperviewEdges()

                return blurEffectView
            }()

            blurEffectView.effect = blurEffect

            // remove hairline below bar.
            self.shadowImage = UIImage()

            // Alter the visual effect view's tint to match our background color
            // so the tabbar, when over a solid color background matching tabBarBackgroundColor,
            // exactly matches the background color. This is brittle, but there is no way to get
            // this behavior from UIVisualEffectView otherwise.
            if
                let tintingView = blurEffectView.subviews.first(where: {
                    String(describing: type(of: $0)) == "_UIVisualEffectSubview"
                })
            {
                tintingView.backgroundColor = tabBarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
                self.backgroundImage = UIImage()
            } else {
                if #available(iOS 17, *) { owsFailDebug("Check if this still works on new iOS version.") }

                owsFailDebug("Unexpectedly missing visual effect subview")
                // If we can't find the tinting subview (e.g. a new iOS version changed the behavior)
                // We'll make the tabBar more translucent by setting a background color.
                let color = tabBarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
                self.backgroundImage = UIImage.image(color: color)
            }
        }
    }

    @objc
    private func themeDidChange() {
        applyTheme()
    }
}
