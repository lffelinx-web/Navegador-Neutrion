import SwiftUI
import WebKit

/// Owns the WKWebView of one tab and publishes its navigation state.
@MainActor
final class TabController: NSObject, ObservableObject {
    let id: UUID
    let webView: WKWebView

    @Published private(set) var title = ""
    @Published private(set) var url: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0

    var onChange: ((TabController) -> Void)?
    var onVisit: ((TabController) -> Void)?
    var onSnapshot: ((UUID, UIImage) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    /// Space left at the bottom of pages for the floating toolbar.
    static let toolbarInset: CGFloat = 76

    init(id: UUID) {
        self.id = id
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInset.bottom = Self.toolbarInset
        webView.scrollView.verticalScrollIndicatorInsets.bottom = Self.toolbarInset

        observations = [
            webView.observe(\.title) { [weak self] _, _ in self?.sync() },
            webView.observe(\.url) { [weak self] _, _ in self?.sync() },
            webView.observe(\.canGoBack) { [weak self] _, _ in self?.sync() },
            webView.observe(\.canGoForward) { [weak self] _, _ in self?.sync() },
            webView.observe(\.isLoading) { [weak self] _, _ in self?.sync() },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in self?.sync() },
        ]
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    func captureSnapshot() {
        guard webView.url != nil, webView.window != nil, webView.bounds.width > 0 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self, let image else { return }
            self.onSnapshot?(self.id, image)
        }
    }

    private func sync() {
        let newTitle = webView.title ?? ""
        if title != newTitle { title = newTitle }
        if url != webView.url, webView.url != nil { url = webView.url }
        if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
        if canGoForward != webView.canGoForward { canGoForward = webView.canGoForward }
        if isLoading != webView.isLoading { isLoading = webView.isLoading }
        if progress != webView.estimatedProgress { progress = webView.estimatedProgress }
        onChange?(self)
    }
}

extension TabController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
        onVisit?(self)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.captureSnapshot()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        sync()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        sync()
    }

    /// Links that ask for a new window (target="_blank") open in the same tab.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
