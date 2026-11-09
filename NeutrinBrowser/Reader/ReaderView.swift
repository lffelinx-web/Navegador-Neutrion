import SwiftUI
import WebKit

/// Distraction-free article view, styled like the Neutrin concept.
struct ReaderView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    let article: ReaderArticle
    let onOpenLink: (URL) -> Void

    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ReaderWebView(article: article, settings: store.readerSettings, ruleLists: store.activeRuleLists) { url in
                dismiss()
                onOpenLink(url)
            }
            .ignoresSafeArea(edges: .bottom)

            HStack(spacing: 2) {
                Button { dismiss() } label: {
                    Label("Listo", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 40)
                }
                Text(article.url?.displayHost ?? "Lectura")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                if let url = article.url {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 40)
                    }
                    .accessibilityLabel("Compartir")
                }
                Button { showSettings = true } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 40)
                }
                .accessibilityLabel("Ajustes de texto")
                .popover(isPresented: $showSettings) {
                    ReaderSettingsPanel(settings: $store.readerSettings)
                        .presentationCompactAdaptation(.popover)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(6)
            .glass(cornerRadius: 28)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .background(Color(.systemBackground))
    }
}

struct ReaderSettingsPanel: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                Button {
                    settings.fontSize = max(ReaderSettings.fontSizeRange.lowerBound, settings.fontSize - 1)
                } label: {
                    Text("A").font(.system(size: 15)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .accessibilityLabel("Texto más pequeño")
                Divider().frame(height: 24)
                Button {
                    settings.fontSize = min(ReaderSettings.fontSizeRange.upperBound, settings.fontSize + 1)
                } label: {
                    Text("A").font(.system(size: 24)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .accessibilityLabel("Texto más grande")
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Picker("Fuente", selection: $settings.font) {
                ForEach(ReaderFont.allCases) { font in
                    Text(font.name).tag(font)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 14) {
                ForEach(ReaderTheme.allCases) { theme in
                    Button { settings.theme = theme } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(swatch(for: theme))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                                .overlay(
                                    Circle().strokeBorder(Color.neutrinBlue, lineWidth: settings.theme == theme ? 3 : 0)
                                )
                                .frame(width: 40, height: 40)
                            Text(theme.name).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(settings.theme == theme ? .isSelected : [])
                }
            }
        }
        .padding(18)
        .frame(width: 290)
    }

    private func swatch(for theme: ReaderTheme) -> AnyShapeStyle {
        switch theme {
        case .auto:
            AnyShapeStyle(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.97), Color(red: 0.07, green: 0.07, blue: 0.09), Color(red: 0.07, green: 0.07, blue: 0.09)],
                                         startPoint: .leading, endPoint: .trailing))
        case .light: AnyShapeStyle(Color(red: 0.97, green: 0.97, blue: 0.99))
        case .sepia: AnyShapeStyle(Color(red: 0.96, green: 0.94, blue: 0.89))
        case .dark: AnyShapeStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
        }
    }
}

/// A locked-down web view for the article: no page JavaScript, no cookies,
/// and the same ad/tracker blocking as normal tabs.
private struct ReaderWebView: UIViewRepresentable {
    let article: ReaderArticle
    let settings: ReaderSettings
    let ruleLists: [WKContentRuleList]
    let onOpenLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onOpenLink: onOpenLink) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        ruleLists.forEach { configuration.userContentController.add($0) }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.contentInset.bottom = TabController.toolbarInset
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(ReaderTemplate.html(for: article, settings: settings), baseURL: article.url)
        context.coordinator.appliedSettings = settings
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenLink = onOpenLink
        guard context.coordinator.appliedSettings != settings else { return }
        context.coordinator.appliedSettings = settings
        webView.evaluateJavaScript(ReaderTemplate.applySettingsScript(settings))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onOpenLink: (URL) -> Void
        var appliedSettings: ReaderSettings?

        init(onOpenLink: @escaping (URL) -> Void) {
            self.onOpenLink = onOpenLink
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // The article itself loads; tapped links open back in the tab.
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                decisionHandler(.cancel)
                if url.isWebURL { onOpenLink(url) }
                return
            }
            decisionHandler(.allow)
        }
    }
}
