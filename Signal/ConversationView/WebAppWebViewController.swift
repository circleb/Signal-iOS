//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import WebKit
import SignalUI
import SignalServiceKit
import PureLayout

class WebAppWebViewController: UIViewController {
    private let webApp: WebApp
    private let webView = WKWebView()
    private let progressView = UIProgressView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    init(webApp: WebApp) {
        self.webApp = webApp
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
        title = webApp.name
        view.backgroundColor = .white

        // Navigation bar setup
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshWebApp)
        )

        // Progress view
        progressView.progressTintColor = .ows_accentBlue
        progressView.trackTintColor = Theme.backgroundColor

        // Loading indicator
        loadingIndicator.hidesWhenStopped = true

        // Layout
        view.addSubview(progressView)
        view.addSubview(webView)
        view.addSubview(loadingIndicator)

        progressView.autoPinEdge(toSuperviewSafeArea: .top)
        progressView.autoPinWidthToSuperview()
        progressView.autoSetDimension(.height, toSize: 2)

        webView.autoPinEdge(.top, to: .bottom, of: progressView)
        webView.autoPinEdgesToSuperviewSafeArea()

        loadingIndicator.autoCenterInSuperview()
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        // Add progress observer
        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
    }

    private func loadWebApp() {
        guard let url = URL(string: "https://\(webApp.entry)") else {
            showError(WebAppsError.invalidURL)
            return
        }

        loadingIndicator.startAnimating()

        let request = URLRequest(url: url)
        webView.load(request)
    }

    @objc private func refreshWebApp() {
        webView.reload()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = webView.estimatedProgress == 1
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
        
        Logger.info("WebApp navigation to: \(url.absoluteString)")
        Logger.info("Navigation type: \(navigationAction.navigationType.rawValue)")
        Logger.info("Target frame: \(navigationAction.targetFrame?.isMainFrame ?? false)")
        Logger.info("Permitted patterns: \(webApp.urlsPermitted)")
        
        // Allow certain types of navigation to stay in-app regardless of patterns
        let shouldAlwaysAllow = shouldAllowNavigationInApp(navigationAction)
        if shouldAlwaysAllow {
            Logger.info("Navigation allowed by type/context")
            decisionHandler(.allow)
            return
        }
        
        // Check URL patterns only for link clicks and new window requests
        let isPermitted = isURLPermitted(url)
        Logger.info("Navigation permitted by URL pattern: \(isPermitted)")
        
        if !isPermitted {
            Logger.warn("Opening URL in external browser: \(url.absoluteString)")
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }
    
    private func shouldAllowNavigationInApp(_ navigationAction: WKNavigationAction) -> Bool {
        // Always allow these types of navigation to stay in the web view
        switch navigationAction.navigationType {
        case .reload:
            return true // Refresh should always work
        case .backForward:
            return true // Back/forward navigation should work
        case .formSubmitted, .formResubmitted:
            return true // Form submissions should work within the app
        case .other:
            // JavaScript-triggered navigation, redirects, etc.
            // Allow if it's in the main frame
            return navigationAction.targetFrame?.isMainFrame == true
        case .linkActivated:
            // Link clicks - check if it's trying to open in a new window
            return navigationAction.targetFrame?.isMainFrame == true
        @unknown default:
            return false
        }
    }
    
    private func isURLPermitted(_ url: URL) -> Bool {
        // If no patterns specified, allow all URLs
        guard !webApp.urlsPermitted.isEmpty else {
            return true
        }
        
        return webApp.urlsPermitted.contains { pattern in
            return matchesPattern(url: url, pattern: pattern)
        }
    }
    
    private func matchesPattern(url: URL, pattern: String) -> Bool {
        // Enhanced pattern matching with better wildcard support
        let urlString = url.absoluteString
        
        // Handle simple cases first
        if pattern == "*" {
            return true
        }
        
        // Convert pattern to regex with proper escaping
        var regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")  // Escape dots
            .replacingOccurrences(of: "*", with: ".*")   // Convert wildcards
        
        // If pattern doesn't start with ^, make it match anywhere in the URL
        if !regexPattern.hasPrefix("^") {
            regexPattern = ".*" + regexPattern
        }
        
        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: .caseInsensitive)
            let matches = regex.matches(in: urlString, options: [], range: NSRange(location: 0, length: urlString.count))
            return !matches.isEmpty
        } catch {
            Logger.warn("Invalid regex pattern: \(pattern), error: \(error)")
            // Fallback to simple contains check
            return urlString.localizedCaseInsensitiveContains(pattern.replacingOccurrences(of: "*", with: ""))
        }
    }
} 