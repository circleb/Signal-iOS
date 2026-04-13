import SwiftUI
import WebKit

struct WebSheetView: UIViewRepresentable {
    let url: URL
    let title: String

    func makeUIView(context: Context) -> WKWebView {
        let wk = WKWebView()
        wk.navigationDelegate = context.coordinator
        wk.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 HMUApp/1.0"
        return wk
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        var req = URLRequest(url: url)
        if let token = SSOUserInfoStore.shared.getUserInfo()?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        webView.load(req)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// Wrapper for pushing inside a NavigationStack as a full view
struct WebPageView: View {
    let url: URL
    let pageTitle: String

    var body: some View {
        WebSheetView(url: url, title: pageTitle)
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(edges: .bottom)
    }
}
