import SwiftUI
import WebKit

/// A loaded web page with the floating Neutrin toolbar.
struct BrowserView: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var controller: TabController
    @Binding var showTabs: Bool

    @State private var isEditing = false
    @State private var addressText = ""
    @State private var showShields = false
    @State private var readerArticle: ReaderArticle?
    @State private var isOpeningReader = false
    @State private var readerFailed = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            WebViewContainer(webView: controller.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { progressBar }

            toolbar
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
        .sheet(isPresented: $showShields) {
            ShieldsPanel(controller: controller).environmentObject(store)
        }
        .fullScreenCover(item: $readerArticle) { article in
            ReaderView(article: article) { url in store.open(url) }
                .environmentObject(store)
        }
        .alert("Reader isn't available for this page", isPresented: $readerFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var progressBar: some View {
        if controller.isLoading {
            GeometryReader { geometry in
                Capsule()
                    .fill(LinearGradient.neutrin)
                    .frame(width: max(geometry.size.width * controller.progress, 24), height: 3)
                    .animation(.easeOut(duration: 0.2), value: controller.progress)
            }
            .frame(height: 3)
            .transition(.opacity)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            if isEditing {
                editingField
            } else {
                ToolbarIcon(symbol: "arrow.left", label: "Back") {
                    if controller.canGoBack { controller.webView.goBack() } else { store.goHome() }
                }
                ToolbarIcon(symbol: "arrow.right", label: "Forward", isEnabled: controller.canGoForward) {
                    controller.webView.goForward()
                }
                addressPill
                ToolbarIcon(symbol: "square.on.square", label: "Tabs") {
                    controller.captureSnapshot()
                    showTabs = true
                }
                moreMenu
            }
        }
        .padding(6)
        .glass(cornerRadius: 28)
        .overlay(alignment: .top) {
            if controller.isPrivate && !isEditing {
                Label("Private", systemImage: "eye.slash")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.indigo, in: Capsule())
                    .offset(y: -10)
            }
        }
        .animation(.snappy, value: isEditing)
    }

    private var shieldsUp: Bool {
        store.shieldsAreConfigured && store.shieldsEnabled(for: controller.url?.host)
    }

    private var addressPill: some View {
        HStack(spacing: 0) {
            Button { showShields = true } label: {
                Image(systemName: shieldsUp ? "shield.lefthalf.filled" : "shield.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(shieldsUp ? Color.neutrinBlue : Color.secondary)
                    .frame(width: 32, height: 40)
                    .overlay(alignment: .topTrailing) {
                        if shieldsUp && !controller.blockedItems.isEmpty {
                            Text("\(min(controller.blockedItems.count, 99))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(Color.neutrinBlue, in: Capsule())
                                .offset(x: 0, y: 3)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(shieldsUp ? "Shields up, \(controller.blockedItems.count) blocked" : "Shields down")

            Button {
                addressText = controller.url?.absoluteString ?? ""
                isEditing = true
            } label: {
                HStack(spacing: 4) {
                    if controller.url?.scheme != "https" {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    Text(controller.url?.displayHost ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Address: \(controller.url?.displayHost ?? "")")

            if controller.isReaderAvailable {
                Button(action: openReader) {
                    Group {
                        if isOpeningReader {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "doc.plaintext")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Reader mode")
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 32, height: 40)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(Color(.systemBackground).opacity(0.55), in: Capsule())
        .animation(.snappy, value: controller.isReaderAvailable)
    }

    private var editingField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
            TextField("Search or enter an address", text: $addressText)
                .focused($addressFocused)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit {
                    store.open(addressText)
                    isEditing = false
                }
                .onAppear { addressFocused = true }
            Button("Cancel") { isEditing = false }
                .font(.subheadline.weight(.semibold))
                .padding(.trailing, 10)
        }
        .frame(height: 40)
    }

    private var moreMenu: some View {
        Menu {
            Button { controller.reloadOrStop() } label: {
                Label(controller.isLoading ? "Stop" : "Reload",
                      systemImage: controller.isLoading ? "xmark" : "arrow.clockwise")
            }
            if let url = controller.url {
                let shareURL = LinkCleaner.cleaned(url)
                ShareLink(item: shareURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                let favorite = store.isFavorite(shareURL)
                Button { store.toggleFavorite(title: controller.title, url: url) } label: {
                    Label(favorite ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: favorite ? "star.slash" : "star")
                }
                Button { UIPasteboard.general.url = shareURL } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
            if controller.isReaderAvailable {
                Button(action: openReader) {
                    Label("Reader Mode", systemImage: "doc.plaintext")
                }
            }
            Picker(selection: $store.privacySettings.websiteDarkMode) {
                ForEach(WebsiteDarkMode.allCases) { mode in
                    Text(mode.name).tag(mode)
                }
            } label: {
                Label("Dark Mode for Websites", systemImage: "moon")
            }
            .pickerStyle(.menu)
            Divider()
            Button { store.newTab(isPrivate: controller.isPrivate) } label: {
                Label(controller.isPrivate ? "New Private Tab" : "New Tab", systemImage: "plus.square.on.square")
            }
            if !controller.isPrivate {
                Button { store.newTab(isPrivate: true) } label: {
                    Label("New Private Tab", systemImage: "eye.slash")
                }
            }
            Button { store.goHome() } label: {
                Label("Start Page", systemImage: "house")
            }
            Button(role: .destructive) { store.close(controller.id) } label: {
                Label("Close Tab", systemImage: "xmark.square")
            }
        } label: {
            ToolbarIconLabel(symbol: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    private func openReader() {
        guard !isOpeningReader else { return }
        isOpeningReader = true
        Task {
            let article = await controller.extractArticle()
            isOpeningReader = false
            if let article {
                readerArticle = article
            } else {
                readerFailed = true
            }
        }
    }
}

private struct ToolbarIconLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }
}

private struct ToolbarIcon: View {
    let symbol: String
    let label: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolbarIconLabel(symbol: symbol)
                .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

/// Hosts a tab's WKWebView. The web view is reused, so it is re-parented when needed.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if webView.superview !== container {
            attach(to: container)
        }
    }

    private func attach(to container: UIView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
