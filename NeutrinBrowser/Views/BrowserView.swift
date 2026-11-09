import SwiftUI
import WebKit

/// A loaded web page with the floating Neutrin toolbar.
struct BrowserView: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var controller: TabController
    @Binding var showTabs: Bool

    @State private var isEditing = false
    @State private var addressText = ""
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
                if let url = controller.url {
                    ShareLink(item: url) { ToolbarIconLabel(symbol: "square.and.arrow.up") }
                        .accessibilityLabel("Share")
                } else {
                    ToolbarIcon(symbol: "square.and.arrow.up", label: "Share", isEnabled: false) {}
                }
                ToolbarIcon(symbol: "square.on.square", label: "Tabs") {
                    controller.captureSnapshot()
                    showTabs = true
                }
                moreMenu
            }
        }
        .padding(6)
        .glass(cornerRadius: 28)
        .animation(.snappy, value: isEditing)
    }

    private var addressPill: some View {
        Button {
            addressText = controller.url?.absoluteString ?? ""
            isEditing = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: controller.url?.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(controller.url?.displayHost ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color(.systemBackground).opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Address: \(controller.url?.displayHost ?? "")")
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
                let favorite = store.isFavorite(url)
                Button { store.toggleFavorite(title: controller.title, url: url) } label: {
                    Label(favorite ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: favorite ? "star.slash" : "star")
                }
                Button { UIPasteboard.general.url = url } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
            Divider()
            Button { store.newTab() } label: {
                Label("New Tab", systemImage: "plus.square.on.square")
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
