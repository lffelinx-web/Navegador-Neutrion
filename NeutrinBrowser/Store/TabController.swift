import SwiftUI
import WebKit

/// Owns the WKWebView of one tab: navigation state, Shields, dark mode and reader detection.
@MainActor
final class TabController: NSObject, ObservableObject {
    let id: UUID
    let isPrivate: Bool
    let webView: WKWebView
    private let contentController: WKUserContentController
    private weak var store: BrowserStore?

    @Published private(set) var title = ""
    @Published private(set) var url: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    /// Ads and trackers stopped on the current page.
    @Published private(set) var blockedItems: [BlockedItem] = []
    @Published private(set) var isReaderAvailable = false
    @Published private(set) var hasOnlySecureContent = true
    /// The toolbar shrinks to a small address pill while the user scrolls down a page.
    @Published private(set) var isToolbarCollapsed = false
    /// The page's theme color (or background), used behind the status bar.
    @Published private(set) var topBarColor: UIColor?

    var onChange: ((TabController) -> Void)?
    var onVisit: ((TabController) -> Void)?
    var onSnapshot: ((UUID, UIImage) -> Void)?
    var onBlocked: (([BlockedItem]) -> Void)?

    private var observations: [NSKeyValueObservation] = []
    private var lastScrollY: CGFloat = 0
    private var forcedLandscape = false

    /// Space left at the bottom of pages for the floating toolbar.
    static let toolbarInset: CGFloat = 76

    private enum MessageName {
        static let shields = "neutrinShields"
        static let reader = "neutrinReader"
        static let fullscreen = "neutrinFullscreen"
    }

    init(id: UUID, isPrivate: Bool, store: BrowserStore) {
        self.id = id
        self.isPrivate = isPrivate
        self.store = store

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = isPrivate ? PrivateSession.dataStore : .default()
        configuration.upgradeKnownHostsToHTTPS = store.privacySettings.upgradeToHTTPS
        // Lets sites like YouTube use real fullscreen, which we rotate to landscape.
        configuration.preferences.isElementFullscreenEnabled = true
        contentController = configuration.userContentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        let messageProxy = ScriptMessageProxy(owner: self)
        contentController.add(messageProxy, contentWorld: .defaultClient, name: MessageName.shields)
        contentController.add(messageProxy, contentWorld: .defaultClient, name: MessageName.reader)
        contentController.add(messageProxy, contentWorld: .defaultClient, name: MessageName.fullscreen)
        installUserScripts()

        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self

        observations = [
            webView.observe(\.title) { [weak self] _, _ in self?.sync() },
            webView.observe(\.url) { [weak self] _, _ in self?.sync() },
            webView.observe(\.canGoBack) { [weak self] _, _ in self?.sync() },
            webView.observe(\.canGoForward) { [weak self] _, _ in self?.sync() },
            webView.observe(\.isLoading) { [weak self] _, _ in self?.sync() },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in self?.sync() },
            webView.observe(\.hasOnlySecureContent) { [weak self] _, _ in self?.sync() },
            webView.observe(\.fullscreenState) { [weak self] _, _ in self?.fullscreenStateChanged() },
            webView.observe(\.themeColor) { [weak self] _, _ in self?.updateTopBarColor() },
            webView.observe(\.underPageBackgroundColor) { [weak self] _, _ in self?.updateTopBarColor() },
            webView.scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in self?.scrollViewDidScroll(scrollView) },
        ]
    }

    // MARK: - Loading

    func load(_ url: URL) {
        let settings = store?.privacySettings ?? PrivacySettings()
        let target = settings.removeTrackingParameters ? LinkCleaner.cleaned(url) : url
        var request = URLRequest(url: target)
        if settings.globalPrivacyControl {
            request.setValue("1", forHTTPHeaderField: "Sec-GPC")
        }
        applyShields(forHost: target.host)
        webView.load(request)
    }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    // MARK: - Shields & scripts

    /// Turns the content blockers on or off for the site about to load.
    func applyShields(forHost host: String?) {
        contentController.removeAllContentRuleLists()
        guard let store, store.shieldsEnabled(for: host) else { return }
        store.activeRuleLists.forEach { contentController.add($0) }
    }

    /// Rebuilds the scripts injected into future pages (after a settings change).
    func installUserScripts() {
        guard let store else { return }
        let settings = store.privacySettings
        contentController.removeAllUserScripts()

        contentController.addUserScript(WKUserScript(
            source: ScriptLibrary.darkMode(enabled: store.websiteDarkModeActive),
            injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient
        ))
        if settings.globalPrivacyControl {
            contentController.addUserScript(WKUserScript(
                source: ScriptLibrary.globalPrivacyControl,
                injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page
            ))
        }
        var categories = Set<Blocklist.Category>()
        if settings.blockAds { categories.insert(.ads) }
        if settings.blockTrackers { categories.insert(.trackers) }
        if !categories.isEmpty {
            contentController.addUserScript(WKUserScript(
                source: ScriptLibrary.shieldsReport,
                injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient
            ))
        }
        contentController.addUserScript(WKUserScript(
            source: ScriptLibrary.fullscreen,
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient
        ))
        contentController.addUserScript(WKUserScript(
            source: ScriptLibrary.reader,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient
        ))
    }

    /// Switches website dark mode on the current page without reloading.
    func setDarkMode(_ enabled: Bool) {
        webView.evaluateJavaScript("window.__neutrinDarkMode && window.__neutrinDarkMode.set(\(enabled))",
                                   in: nil, in: .defaultClient) { _ in }
    }

    // MARK: - Reader

    /// Runs Readability on a copy of the page. Returns `nil` if no article was found.
    func extractArticle() async -> ReaderArticle? {
        let body = """
        const article = new Readability(document.cloneNode(true)).parse();
        return article ? JSON.stringify(article) : "";
        """
        let pageURL = url
        return await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .defaultClient) { result in
                guard case .success(let value) = result,
                      let json = value as? String, !json.isEmpty,
                      var article = try? JSONDecoder().decode(ReaderArticle.self, from: Data(json.utf8)),
                      !(article.content ?? "").isEmpty
                else {
                    continuation.resume(returning: nil)
                    return
                }
                article.url = pageURL
                continuation.resume(returning: article)
            }
        }
    }

    // MARK: - Toolbar & fullscreen

    func setToolbarCollapsed(_ collapsed: Bool) {
        if isToolbarCollapsed != collapsed { isToolbarCollapsed = collapsed }
    }

    /// Collapses the toolbar when the user scrolls down and brings it back when
    /// they scroll up or reach the top or bottom of the page.
    private func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        defer { lastScrollY = y }
        // Ignore programmatic scrolling (page loads, anchors) – only react to the user.
        guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else { return }
        let bottom = scrollView.contentSize.height - scrollView.bounds.height
            + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom
        let delta = y - lastScrollY
        if y < 24 || y > bottom - 24 {
            setToolbarCollapsed(false)
        } else if delta > 4 {
            setToolbarCollapsed(true)
        } else if delta < -10 {
            setToolbarCollapsed(false)
        }
    }

    private func updateTopBarColor() {
        let color = webView.themeColor ?? webView.underPageBackgroundColor
        if topBarColor != color { topBarColor = color }
    }

    /// Element fullscreen (requestFullscreen) as reported by WebKit.
    private func fullscreenStateChanged() {
        switch webView.fullscreenState {
        case .inFullscreen:
            let script = """
            (() => {
              const el = document.fullscreenElement || document.webkitFullscreenElement;
              const video = el ? (el.tagName === "VIDEO" ? el : el.querySelector("video")) : document.querySelector("video");
              return video && video.videoHeight ? video.videoWidth / video.videoHeight : 0;
            })()
            """
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                self?.videoFullscreenChanged(active: true, aspectRatio: (result as? Double) ?? 0)
            }
        case .notInFullscreen:
            videoFullscreenChanged(active: false, aspectRatio: 0)
        default:
            break
        }
    }

    /// Fullscreen video (element fullscreen or iOS's native video player):
    /// rotate to landscape for wide videos, back to portrait afterwards.
    func videoFullscreenChanged(active: Bool, aspectRatio: Double) {
        if active {
            // Unknown size (0) is treated as a normal wide video.
            guard !forcedLandscape, aspectRatio == 0 || aspectRatio > 1.05 else { return }
            forcedLandscape = true
            DeviceOrientation.request(.landscapeRight)
        } else if forcedLandscape {
            forcedLandscape = false
            DeviceOrientation.request(.portrait)
        }
    }

    // MARK: - Snapshots & state

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
        if hasOnlySecureContent != webView.hasOnlySecureContent { hasOnlySecureContent = webView.hasOnlySecureContent }
        onChange?(self)
    }

    fileprivate func handle(_ message: WKScriptMessage) {
        switch message.name {
        case MessageName.shields:
            guard let reports = message.body as? [[String: Any]], let store,
                  store.shieldsEnabled(for: url?.host) else { return }
            var known = Set(blockedItems)
            var fresh: [BlockedItem] = []
            for report in reports {
                guard let host = report["host"] as? String,
                      let category = store.blockedCategory(host: host, path: report["path"] as? String ?? "/",
                                                           pageHost: url?.host) else { continue }
                let item = BlockedItem(host: host, category: category)
                if known.insert(item).inserted { fresh.append(item) }
            }
            guard !fresh.isEmpty else { return }
            blockedItems.append(contentsOf: fresh)
            onBlocked?(fresh)
        case MessageName.fullscreen:
            if let body = message.body as? [String: Any], let active = body["active"] as? Bool {
                videoFullscreenChanged(active: active, aspectRatio: (body["ratio"] as? Double) ?? 0)
            }
        case MessageName.reader:
            if let body = message.body as? [String: Any], let readerable = body["readerable"] as? Bool {
                isReaderAvailable = readerable
            }
        default:
            break
        }
    }
}

// MARK: - WebKit delegates

extension TabController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if !url.isWebURL {
            let scheme = url.scheme?.lowercased() ?? ""
            let isInternalScheme = ["about", "blob", "data", "javascript", "file"].contains(scheme)
            if !isInternalScheme, navigationAction.navigationType == .linkActivated {
                // mailto:, tel:, maps, App Store… open in their apps.
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            return
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame {
            let settings = store?.privacySettings ?? PrivacySettings()
            if settings.removeTrackingParameters,
               navigationAction.request.httpMethod == "GET",
               let cleaned = LinkCleaner.clean(url) {
                decisionHandler(.cancel)
                load(cleaned)
                return
            }
            applyShields(forHost: url.host)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        blockedItems = []
        isReaderAvailable = false
        setToolbarCollapsed(false)
        sync()
    }

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
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            load(url)
        }
        return nil
    }
}

/// WKUserContentController keeps its handlers alive; this proxy avoids a retain cycle.
@MainActor
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: TabController?

    init(owner: TabController) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.handle(message)
    }
}

/// One shared, in-memory website data store for all private tabs.
/// It's thrown away when the last private tab closes.
@MainActor
enum PrivateSession {
    private static var current: WKWebsiteDataStore?

    static var dataStore: WKWebsiteDataStore {
        if let current { return current }
        let store = WKWebsiteDataStore.nonPersistent()
        current = store
        return store
    }

    static func end() {
        current = nil
    }
}

/// Loads the bundled JavaScript once.
@MainActor
enum ScriptLibrary {
    private static func file(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Missing script \(name).js")
            return ""
        }
        return source
    }

    private static let darkModeTemplate = file("NeutrinDarkMode")
    static let shieldsReport = file("NeutrinShields")
    static let globalPrivacyControl = file("NeutrinGPC")
    static let fullscreen = file("NeutrinFullscreen")
    static let reader = [file("Readability"), file("Readability-readerable"), file("NeutrinReader")].joined(separator: "\n;\n")

    static func darkMode(enabled: Bool) -> String {
        darkModeTemplate.replacingOccurrences(of: "__NEUTRIN_DARK_ENABLED__", with: enabled ? "true" : "false")
    }
}

/// Rotates the app's window, e.g. into landscape for a fullscreen video.
@MainActor
enum DeviceOrientation {
    static func request(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
    }
}
