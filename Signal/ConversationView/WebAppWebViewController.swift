//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import WebKit
import SignalUI
import SignalServiceKit
import PureLayout

class WebAppWebViewController: UIViewController, OWSNavigationChildController {
    private let webApp: WebApp
    private let webAppsService: WebAppsServiceProtocol
    private let userInfoStore: SSOUserInfoStore
    private let webView = WKWebView()
    private let progressView = UIProgressView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private var isLoadingBlockedMessage = false
    

    init(webApp: WebApp, webAppsService: WebAppsServiceProtocol, userInfoStore: SSOUserInfoStore = SSOUserInfoStoreImpl()) {
        self.webApp = webApp
        self.webAppsService = webAppsService
        self.userInfoStore = userInfoStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupWebView()
        loadWebApp()
    }

    private func setupUI() {
        view.backgroundColor = .white

        // Navigation bar setup with back, forward, and refresh buttons
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
        
        navigationItem.rightBarButtonItems = [refreshButton, forwardButton, backButton]

        // Progress view
        progressView.progressTintColor = .ows_accentBlue
        progressView.trackTintColor = Theme.backgroundColor

        // Loading indicator
        loadingIndicator.hidesWhenStopped = true

        // Layout
        view.addSubview(webView)
        view.addSubview(progressView)
        view.addSubview(loadingIndicator)

        webView.autoPinEdgesToSuperviewSafeArea()

        progressView.autoPinEdge(.bottom, to: .bottom, of: webView)
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
        if let requiredRole = webApp.kcRole {
            let userRoles = userInfoStore.getUserRoles()
            if !userRoles.contains(requiredRole) {
                showAccessDeniedError(requiredRole: requiredRole)
                return
            }
        }
        
        guard let url = URL(string: "https://\(webApp.entry)") else {
            showError(WebAppsError.invalidURL)
            return
        }

        loadingIndicator.startAnimating()

        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    private func showAccessDeniedError(requiredRole: String) {
        let alert = UIAlertController(
            title: "Access Denied",
            message: "You need the '\(requiredRole)' role to access this application.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func refreshWebApp() {
        webView.reload()
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

extension WebAppWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        isLoadingBlockedMessage = false
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
        let blockedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background-color: #f8f9fa;
                    margin: 0;
                    padding: 20px;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                }
                .blocked-container {
                    background: white;
                    border-radius: 12px;
                    padding: 40px;
                    text-align: center;
                    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
                    max-width: 400px;
                }
                .blocked-icon {
                    font-size: 48px;
                    margin-bottom: 20px;
                }
                .blocked-title {
                    font-size: 24px;
                    font-weight: 600;
                    color: #dc3545;
                    margin-bottom: 12px;
                }
                .blocked-message {
                    font-size: 16px;
                    color: #6c757d;
                    line-height: 1.5;
                    margin-bottom: 20px;
                }
                .blocked-info {
                    font-size: 14px;
                    color: #adb5bd;
                    background: #f8f9fa;
                    padding: 12px;
                    border-radius: 6px;
                }
            </style>
        </head>
        <body>
            <div class="blocked-container">
                <div class="blocked-icon">🚫</div>
                <div class="blocked-title">Access Blocked</div>
                <div class="blocked-message">
                    Only approved websites are allowed in this web app.
                </div>
            </div>
        </body>
        </html>
        """
        
        webView.loadHTMLString(blockedHTML, baseURL: nil)
    }
    
    private func isSpecialURL(_ url: URL) -> Bool {
        let specialSchemes = ["about", "data", "file", "javascript"]
        return specialSchemes.contains(url.scheme?.lowercased() ?? "")
    }
}

 