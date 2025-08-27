//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import WebKit
import SignalUI
import SignalServiceKit
import PureLayout
import SwiftUI

class WebAppWebViewController: UIViewController, OWSNavigationChildController, WKNavigationDelegate {
    private let webApp: WebApp
    private let webAppsService: WebAppsServiceProtocol
    private let userInfoStore: SSOUserInfoStore
    private let webView = WKWebView()
    private static var restoredCookies = false
    private let progressView = UIProgressView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private var isLoadingBlockedMessage = false
    private var blockedURL: String?
    
    // Pinning functionality
    private var pinnedURLsService: PinnedURLsServiceProtocol {
        return webAppsService.getPinnedURLsService()
    }
    
    init(webApp: WebApp, webAppsService: WebAppsServiceProtocol, userInfoStore: SSOUserInfoStore = SSOUserInfoStoreImpl()) {
        self.webApp = webApp
        self.webAppsService = webAppsService
        self.userInfoStore = userInfoStore
        super.init(nibName: nil, bundle: nil)
        
        // Set title and hide bottom bar when pushed (like ConversationViewController)
        self.title = webApp.name
        self.hidesBottomBarWhenPushed = true
    }
    
    // Convenience initializer for opening Bookmarks
    convenience init(url: URL, title: String) {
        // Create a dummy WebApp for the Bookmark
        let dummyWebApp = WebApp(
            entry: url.host ?? "bookmark",
            name: title,
            description: "Bookmark",
            icon: "link",
            image: "",
            category: "Bookmark",
            urlsPermitted: [url.absoluteString],
            location: [],
            type: "bookmark",
            parent: ""
        )
        
        // Create WebAppsService instance
        let cache = WebAppsStoreImpl(keyValueStore: KeyValueStore(collection: "WebApps"))
        let webAppsService = WebAppsService(
            networkManager: SSKEnvironment.shared.networkManagerRef,
            cache: cache,
            databaseStorage: SSKEnvironment.shared.databaseStorageRef
        )
        
        self.init(
            webApp: dummyWebApp,
            webAppsService: webAppsService,
            userInfoStore: SSOUserInfoStoreImpl()
        )
        
        // Override the title
        self.title = title
        
        // Load the specific URL instead of the webapp entry
        self.loadSpecificURL(url)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupWebView()
        setupPinningButtons()
        
        // Restore cookies if not already done
        if !WebAppWebViewController.restoredCookies {
            restoreCookies()
            WebAppWebViewController.restoredCookies = true
        }
        
        loadWebApp()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Configure navigation bar for transparent background with blur
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground() // gives you the system blur
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        
        // Check if we're in collapsed mode (iPhone or narrow iPad)
        let isCollapsed = splitViewController?.isCollapsed ?? true
        // Navigation bar setup with back, forward, and refresh buttons on the left
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(goBack)
        )

        let forwardButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.right"),
            style: .plain,
            target: self,
            action: #selector(goForward)
        )
        
        let refreshButton = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshWebApp)
        )
        
        if isCollapsed {
            // On iPhone/narrow iPad, show close button instead of back button
            let closeButton = UIBarButtonItem(
                image: UIImage(systemName: "xmark"),
                style: .plain,
                target: self,
                action: #selector(closeButtonTapped)
            )
            
            navigationItem.leftBarButtonItems = [closeButton, backButton, forwardButton]
            navigationItem.rightBarButtonItem = refreshButton
            navigationItem.hidesBackButton = true
            navigationItem.title = nil // Hide title in collapsed view
        } else {
            // On wide iPad, show standard back button for split view navigation
            navigationItem.leftBarButtonItems = [backButton, forwardButton]
            navigationItem.rightBarButtonItem = refreshButton
            // Title is already set in init, keep it for expanded view
        }
        
        // Progress view
        progressView.progressTintColor = .ows_accentBlue
        progressView.trackTintColor = Theme.backgroundColor
        
        // Loading indicator
        loadingIndicator.hidesWhenStopped = true
        
        // Layout
        view.addSubview(webView)
        view.addSubview(progressView)
        view.addSubview(loadingIndicator)
        
        // Pin webview to superview edges to allow overflow behind navigation bar
        webView.autoPinEdgesToSuperviewEdges()
        
        progressView.autoPinEdge(.top, to: .top, of: webView)
        progressView.autoPinWidthToSuperview()
        progressView.autoSetDimension(.height, toSize: 2)
        
        loadingIndicator.autoCenterInSuperview()
    }
    
    private func setupWebView() {
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        
        // Set custom user agent to identify Signal app web view
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.3 Mobile/15E148 Safari/604.1 HCPApp/2.0"
        
        // Add progress observer
        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
    }
    
    private func loadWebApp() {
        // Check if user has required role for this webapp
        if let requiredRoles = webApp.kcRole {
            let userRoles = userInfoStore.getUserRoles()
            // User needs to have at least one of the required roles
            let hasRequiredRole = requiredRoles.contains { requiredRole in
                userRoles.contains(requiredRole)
            }
            if !hasRequiredRole {
                showAccessDeniedError(requiredRoles: requiredRoles)
                return
            }
        }
        
        guard let url = URL(string: "https://\(webApp.entry)") else {
            showError(WebAppsError.invalidURL)
            return
        }
        
        loadSpecificURL(url)
    }
    
    private func loadSpecificURL(_ url: URL) {
        loadingIndicator.startAnimating()
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    private func saveCookies() {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.httpCookieStore.getAllCookies { cookies in
            let cookiesData = cookies.map { cookie in
                return [
                    "name": cookie.name,
                    "value": cookie.value,
                    "domain": cookie.domain,
                    "path": cookie.path,
                    "secure": cookie.isSecure,
                    "expiresDate": cookie.expiresDate ?? Date.distantFuture
                ] as [String : Any]
            }
            UserDefaults.standard.set(cookiesData, forKey: "webapp_cookies")
            Logger.info("Saved \(cookies.count) cookies to UserDefaults")
        }
    }
    
    private func restoreCookies() {
        let dataStore = WKWebsiteDataStore.default()
        if let cookiesData = UserDefaults.standard.array(forKey: "webapp_cookies") as? [[String: Any]] {
            for cookieData in cookiesData {
                if let cookie = HTTPCookie(properties: [
                    .name: cookieData["name"]!,
                    .value: cookieData["value"]!,
                    .domain: cookieData["domain"]!,
                    .path: cookieData["path"]!,
                    .secure: cookieData["secure"]!,
                    .expires: cookieData["expiresDate"]!
                ]) {
                    dataStore.httpCookieStore.setCookie(cookie, completionHandler: nil)
                }
            }
            Logger.info("Restored \(cookiesData.count) cookies from UserDefaults")
        }
    }
    
    // Static method to clear cookies when user signs out
    static func clearAllCookies() {
        // Remove saved cookies from UserDefaults
        UserDefaults.standard.removeObject(forKey: "webapp_cookies")
        
        // Clear cookies from WKWebsiteDataStore
        let dataStore = WKWebsiteDataStore.default()
        dataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                dataStore.httpCookieStore.delete(cookie) {
                    Logger.info("Deleted cookie: \(cookie.name) for domain: \(cookie.domain)")
                }
            }
            Logger.info("Cleared \(cookies.count) cookies from WKWebsiteDataStore")
        }
        
        // Reset the restored cookies flag
        restoredCookies = false
        
        Logger.info("Cleared all saved cookies and reset restoration flag")
    }
    
    private func setupPinningButtons() {
        // Only show pinning buttons for real webapps, not Bookmarks
        if webApp.type != "bookmark" {
            setupPinnedURLsButton()
        }
    }
    
    private func showAccessDeniedError(requiredRoles: [String]) {
        let rolesText = requiredRoles.joined(separator: ", ")
        let alert = UIAlertController(
            title: "Access Denied",
            message: "You need one of the following roles to access this application: \(rolesText)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    
    @objc private func refreshWebApp() {
        webView.reload()
    }
    
    @objc private func closeButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    @objc private func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
    

    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = webView.estimatedProgress == 1.0
        }
    }
    
    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    deinit {
        webView.removeObserver(self, forKeyPath: "estimatedProgress")
    }
}

// MARK: - WKNavigationDelegate

extension WebAppWebViewController {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        isLoadingBlockedMessage = false
        
        // Save cookies after each page load
        saveCookies()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        showError(error)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        // Allow special URLs and when loading blocked message
        if isLoadingBlockedMessage || isSpecialURL(url) {
            decisionHandler(.allow)
            return
        }
        
        Logger.info("WebApp navigation to: \(url.absoluteString)")
        Logger.info("Permitted patterns: \(webApp.urlsPermitted)")
        Logger.info("Global allow list: \(webAppsService.getCachedGlobalAllowList()?.map { $0.entry } ?? [])")
        
        // Check if URL is permitted based on urlsPermitted patterns
        let isPermitted = isURLPermitted(url)
        Logger.info("Navigation permitted by URL pattern: \(isPermitted)")
        
        if !isPermitted {
            Logger.warn("🚫 BLOCKED URL: \(url.absoluteString)")
            Logger.warn("📋 WebApp: \(webApp.name) (entry: \(webApp.entry))")
            Logger.warn("🔍 URL Patterns Checked: \(webApp.urlsPermitted)")
            Logger.warn("❌ URL did not match any permitted patterns")
            Logger.warn("🌐 Navigation Type: \(navigationAction.navigationType.rawValue)")
            Logger.warn("📱 Target Frame: \(navigationAction.targetFrame?.isMainFrame ?? false ? "Main Frame" : "Sub Frame")")
            
            blockedURL = url.absoluteString
            isLoadingBlockedMessage = true
            showBlockedMessage()
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }
    
    private func isURLPermitted(_ url: URL) -> Bool {
        // First check if URL is globally allowed
        if webAppsService.isURLGloballyAllowed(url) {
            Logger.info("✅ URL globally allowed: \(url.absoluteString)")
            return true
        }
        
        // If no patterns specified, allow all URLs
        guard !webApp.urlsPermitted.isEmpty else {
            return true
        }
        
        let urlString = url.absoluteString.lowercased()
        
        return webApp.urlsPermitted.contains { pattern in
            return matchesPattern(urlString: urlString, pattern: pattern.lowercased())
        }
    }
    
    private func matchesPattern(urlString: String, pattern: String) -> Bool {
        // Handle wildcard patterns
        if pattern == "*" {
            return true
        }
        
        // Simple wildcard matching
        if pattern.contains("*") {
            let regexPattern = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            
            do {
                let regex = try NSRegularExpression(pattern: regexPattern, options: .caseInsensitive)
                let range = NSRange(location: 0, length: urlString.count)
                return regex.firstMatch(in: urlString, options: [], range: range) != nil
            } catch {
                Logger.warn("Invalid regex pattern: \(pattern), error: \(error)")
                return false
            }
        }
        
        // Simple substring matching
        return urlString.contains(pattern)
    }
    
    private func showBlockedMessage() {
        // Hide the web view and show the native blocked message
        webView.isHidden = true
        loadingIndicator.stopAnimating()
        
        // Hide the navigation bar
        navigationController?.setNavigationBarHidden(true, animated: true)
        
        // Create and add the blocked message view
        let blockedMessageView = BlockedMessageView(
            blockedURL: blockedURL ?? "Unknown URL",
            onGoBack: { [weak self] in
                self?.handleGoBackFromBlockedMessage()
            },
            onRequestAccess: { [weak self] in
                self?.showAccessRequestForm()
            }
        )
        
        let hostingController = HostingController(wrappedView: blockedMessageView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.autoPinEdgesToSuperviewEdges()
        hostingController.didMove(toParent: self)
    }
    
    private func handleGoBackFromBlockedMessage() {
        // Remove the blocked message view
        for child in children {
            if child is HostingController<BlockedMessageView> {
                child.willMove(toParent: nil)
                child.view.removeFromSuperview()
                child.removeFromParent()
                break
            }
        }
        
        // Show the navigation bar again
        navigationController?.setNavigationBarHidden(false, animated: true)
        
        // Show the web view again and go back
        webView.isHidden = false
        isLoadingBlockedMessage = false
        blockedURL = nil
        
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    private func showAccessRequestForm() {
        guard let blockedURL = blockedURL,
              let userInfo = userInfoStore.getUserInfo() else {
            return
        }
        
        let formView = AccessRequestFormView(
            blockedURL: blockedURL,
            userInfo: userInfo
        )
        
        let hostingController = HostingController(wrappedView: formView)
        
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        
        present(hostingController, animated: true)
    }
    
    private func isSpecialURL(_ url: URL) -> Bool {
        let specialSchemes = ["about", "data", "file", "javascript"]
        return specialSchemes.contains(url.scheme?.lowercased() ?? "")
    }
    
    // MARK: - Pinning Functionality
    
    private func showPinURLAlert() {
        let alert = UIAlertController(title: "Add Bookmark", message: nil, preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Title for this bookmark"
            textField.text = self.webView.title ?? "Bookmark"
        }
        
        let pinAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self,
                  let title = alert.textFields?[0].text,
                  !title.isEmpty,
                  let currentURL = self.webView.url?.absoluteString else {
                return
            }
            
            let icon = "link"
            
            Task {
                do {
                    try await self.pinnedURLsService.pinURL(
                        currentURL,
                        title: title,
                        webApp: self.webApp,
                        icon: icon
                    )
                    
                    DispatchQueue.main.async {
                        self.showPinSuccessAlert()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showPinErrorAlert(error)
                    }
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(pinAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func showPinSuccessAlert() {
        let alert = UIAlertController(
            title: "URL Bookmark",
            message: "This URL has been added to your Bookmarks.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showPinErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: "Failed to pin URL: \(error.localizedDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func setupPinnedURLsButton() {
        let pinnedURLsButton = UIBarButtonItem(
            image: UIImage(systemName: "book"),
            style: .plain,
            target: self,
            action: #selector(pinnedURLsButtonTapped)
        )
        
        // Add to right side of navigation bar
        if var rightBarButtonItems = navigationItem.rightBarButtonItems {
            rightBarButtonItems.insert(pinnedURLsButton, at: 0)
            navigationItem.rightBarButtonItems = rightBarButtonItems
        } else {
            navigationItem.rightBarButtonItems = [pinnedURLsButton]
        }
    }
    
    @objc private func pinnedURLsButtonTapped() {
        showPinnedURLsHalfSheet()
    }
    
    private func showPinnedURLsHalfSheet() {
        let pinnedURLs = pinnedURLsService.getPinnedURLs(for: webApp)
        let halfSheetVC = PinnedURLsHalfSheetViewController(
            pinnedURLs: pinnedURLs,
            pinnedURLsService: pinnedURLsService,
            onAddBookmark: { [weak self] in
                self?.showPinURLAlert()
            },
            onSelectBookmark: { [weak self] pinnedURL in
                self?.openPinnedURL(pinnedURL)
            }
        )
        
        let navigationController = UINavigationController(rootViewController: halfSheetVC)
        
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [UISheetPresentationController.Detent.medium(), UISheetPresentationController.Detent.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        
        present(navigationController, animated: true)
    }
    
    private func openPinnedURL(_ pinnedURL: PinnedURL) {
        // Record access
        Task {
            await pinnedURLsService.recordAccess(for: pinnedURL.id)
        }
        
        // Open URL in webview
        if let url = URL(string: pinnedURL.url) {
            loadSpecificURL(url)
        }
    }
}

// MARK: - PinnedURLsHalfSheetViewController

class PinnedURLsHalfSheetViewController: UIViewController {
    private var pinnedURLs: [PinnedURL]
    private let pinnedURLsService: PinnedURLsServiceProtocol
    private let onAddBookmark: () -> Void
    private let onSelectBookmark: (PinnedURL) -> Void
    
    private let tableView = UITableView()
    private let addButton = UIButton(type: .system)
    
    init(
        pinnedURLs: [PinnedURL],
        pinnedURLsService: PinnedURLsServiceProtocol,
        onAddBookmark: @escaping () -> Void,
        onSelectBookmark: @escaping (PinnedURL) -> Void
    ) {
        self.pinnedURLs = pinnedURLs
        self.pinnedURLsService = pinnedURLsService
        self.onAddBookmark = onAddBookmark
        self.onSelectBookmark = onSelectBookmark
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = Theme.backgroundColor
        
        // Setup navigation bar
        navigationItem.title = "Bookmarks"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissTapped)
        )
        
        // Setup add button
        addButton.setTitle("Add Current Page", for: .normal)
        addButton.setTitleColor(.ows_accentBlue, for: .normal)
        addButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        addButton.addTarget(self, action: #selector(addBookmarkTapped), for: .touchUpInside)
        
        // Setup table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PinnedURLCompactCell.self, forCellReuseIdentifier: "PinnedURLCompactCell")
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        
        // Layout
        view.addSubview(addButton)
        view.addSubview(tableView)
        
        addButton.autoPinEdge(.top, to: .top, of: view, withOffset: 60)
        addButton.autoPinEdge(.leading, to: .leading, of: view, withOffset: 16)
        addButton.autoPinEdge(.trailing, to: .trailing, of: view, withOffset: -16)
        
        tableView.autoPinEdge(.top, to: .bottom, of: addButton, withOffset: 16)
        tableView.autoPinEdge(.leading, to: .leading, of: view)
        tableView.autoPinEdge(.trailing, to: .trailing, of: view)
        tableView.autoPinEdge(.bottom, to: .bottom, of: view)
    }
    
    @objc private func dismissTapped() {
        dismiss(animated: true)
    }
    
    @objc private func addBookmarkTapped() {
        dismiss(animated: true) {
            self.onAddBookmark()
        }
    }
}

// MARK: - UITableViewDataSource

extension PinnedURLsHalfSheetViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return pinnedURLs.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PinnedURLCompactCell", for: indexPath) as! PinnedURLCompactCell
        let pinnedURL = pinnedURLs[indexPath.row]
        cell.configure(with: pinnedURL)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension PinnedURLsHalfSheetViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let pinnedURL = pinnedURLs[indexPath.row]
        dismiss(animated: true) {
            self.onSelectBookmark(pinnedURL)
        }
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let pinnedURL = pinnedURLs[indexPath.row]
            deleteBookmark(pinnedURL, at: indexPath)
        }
    }
    
    private func deleteBookmark(_ pinnedURL: PinnedURL, at indexPath: IndexPath) {
        Task {
            do {
                try await pinnedURLsService.unpinURL(pinnedURL.id)
                
                DispatchQueue.main.async {
                    // Remove from data source and update UI
                    self.pinnedURLs.remove(at: indexPath.row)
                    
                    // Update the table view
                    self.tableView.deleteRows(at: [indexPath], with: .fade)
                    
                    // Show success feedback
                    self.showDeleteSuccessToast()
                }
            } catch {
                DispatchQueue.main.async {
                    self.showDeleteErrorAlert(error)
                }
            }
        }
    }
    
    private func showDeleteSuccessToast() {
        let toastController = ToastController(text: "Bookmark deleted")
        toastController.presentToastView(
            from: .bottom,
            of: self.view,
            inset: 40
        )
    }
    
    private func showDeleteErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: "Failed to delete bookmark: \(error.localizedDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - PinnedURLCompactCell

class PinnedURLCompactCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let urlLabel = UILabel()
    private let iconImageView = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .default
        
        // Setup icon
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .ows_accentBlue
        
        // Setup title label
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.numberOfLines = 1
        
        // Setup URL label
        urlLabel.font = .preferredFont(forTextStyle: .caption1)
        urlLabel.textColor = Theme.secondaryTextAndIconColor
        urlLabel.numberOfLines = 1
        
        // Layout
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(urlLabel)
        
        iconImageView.autoSetDimensions(to: CGSize(width: 20, height: 20))
        iconImageView.autoPinEdge(.leading, to: .leading, of: contentView, withOffset: 16)
        iconImageView.autoAlignAxis(.horizontal, toSameAxisOf: contentView)
        
        titleLabel.autoPinEdge(.leading, to: .trailing, of: iconImageView, withOffset: 12)
        titleLabel.autoPinEdge(.trailing, to: .trailing, of: contentView, withOffset: -16)
        titleLabel.autoPinEdge(.top, to: .top, of: contentView, withOffset: 8)
        
        urlLabel.autoPinEdge(.leading, to: .leading, of: titleLabel)
        urlLabel.autoPinEdge(.trailing, to: .trailing, of: titleLabel)
        urlLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 2)
        urlLabel.autoPinEdge(.bottom, to: .bottom, of: contentView, withOffset: -8)
    }
    
    func configure(with pinnedURL: PinnedURL) {
        titleLabel.text = pinnedURL.title
        
        // Format URL for display
        if let url = URL(string: pinnedURL.url) {
            urlLabel.text = url.host ?? pinnedURL.url
        } else {
            urlLabel.text = pinnedURL.url
        }
        
        // Set icon
        if let iconName = pinnedURL.icon {
            iconImageView.image = UIImage(systemName: iconName)
        } else {
            iconImageView.image = UIImage(systemName: "link")
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        urlLabel.text = nil
        iconImageView.image = nil
    }
}
