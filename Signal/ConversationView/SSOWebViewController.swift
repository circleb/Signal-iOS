//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import WebKit
import SignalServiceKit
import SignalUI

class SSOWebViewController: UIViewController {
    
    private let url: URL
    private let pageTitle: String
    private let userInfoStore: SSOUserInfoStore
    private let webView = WKWebView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let closeButton = UIBarButtonItem(
        barButtonSystemItem: .close,
        target: nil,
        action: nil
    )
    
    private var estimatedProgress: Float = 0.0 {
        didSet {
            progressView.setProgress(estimatedProgress, animated: true)
            progressView.isHidden = estimatedProgress >= 1.0
        }
    }
    
    init(url: URL, title: String, userInfoStore: SSOUserInfoStore = SSOUserInfoStoreImpl()) {
        self.url = url
        self.pageTitle = title
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
        loadURL()
    }
    
    private func setupUI() {
        self.title = pageTitle
        view.backgroundColor = Theme.backgroundColor
        
        // Navigation bar setup
        closeButton.target = self
        closeButton.action = #selector(closeButtonTapped)
        navigationItem.leftBarButtonItem = closeButton
        
        // Progress view setup
        progressView.progressTintColor = Theme.accentBlueColor
        progressView.trackTintColor = Theme.secondaryBackgroundColor
        progressView.isHidden = true
        
        // Layout
        view.addSubview(webView)
        view.addSubview(progressView)
        
        webView.autoPinEdgesToSuperviewEdges()
        progressView.autoPinEdge(.top, to: .top, of: view)
        progressView.autoPinEdge(.leading, to: .leading, of: view)
        progressView.autoPinEdge(.trailing, to: .trailing, of: view)
        progressView.autoSetDimension(.height, toSize: 2)
    }
    
    private func setupWebView() {
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        
        // Add progress observer
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.3 Mobile/15E148 Safari/604.1 HCPApp/2.0"
    }
    
    private func loadURL() {
        guard let userInfo = userInfoStore.getUserInfo() else {
            showError("No SSO authentication found. Please sign in again.")
            return
        }
        
        let accessToken = userInfo.accessToken
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Add cache control to prevent caching issues
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        webView.load(request)
    }
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(WKWebView.estimatedProgress) {
            estimatedProgress = Float(webView.estimatedProgress)
        }
    }
    
    deinit {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }
}

// MARK: - WKNavigationDelegate

extension SSOWebViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        estimatedProgress = 0.0
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        estimatedProgress = 1.0
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        estimatedProgress = 1.0
        showError("Failed to load page: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        estimatedProgress = 1.0
        showError("Failed to load page: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow all navigation
        decisionHandler(.allow)
    }
}
