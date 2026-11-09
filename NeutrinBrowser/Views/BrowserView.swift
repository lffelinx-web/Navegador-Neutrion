import SwiftUI
import WebKit

/// A loaded web page with the Neutrin toolbar underneath.
struct BrowserView: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var controller: TabController
    @Binding var showTabs: Bool

    @State private var isEditing = false
    @State private var addressText = ""
    @State private var showShields = false
    @State private var showReaderSettings = false
    @State private var isOpeningReader = false
    @State private var readerFailed = false
    @State private var showSettings = false
    @FocusState private var addressFocused: Bool

    private var collapsed: Bool { controller.isToolbarCollapsed && !isEditing }

    /// Color behind the clock / Dynamic Island: whatever is at the top of the page.
    private var topColor: UIColor {
        controller.pageTopColor ?? controller.topBarColor ?? .systemBackground
    }

    /// Color behind the toolbar: whatever is at the bottom of the page.
    private var bottomColor: UIColor {
        controller.pageBottomColor ?? .systemBackground
    }

    var body: some View {
        // The page sits between the status bar and the toolbar, never underneath them,
        // so sticky headers and bottom bars of websites stay visible.
        VStack(spacing: 0) {
            WebViewContainer(webView: controller.webView)
                .overlay(alignment: .top) { progressBar }
            bottomBar
        }
        // When collapsed, the address line moves into the home-indicator strip, like Safari.
        .ignoresSafeArea(.container, edges: collapsed ? .bottom : [])
        .background {
            VStack(spacing: 0) {
                statusBarBackground
                Color(uiColor: bottomColor)
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.3), value: topColor)
            .animation(.easeInOut(duration: 0.3), value: bottomColor)
        }
        // Clock and battery switch to light text on dark pages (only while browsing).
        .background(WindowAppearance(style: windowStyle))
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsPanel(settings: $store.readerSettings)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: store.readerSettings) { _, settings in
            controller.applyReaderSettings(settings)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
        .sheet(isPresented: $showShields) {
            ShieldsPanel(controller: controller).environmentObject(store)
        }
        .alert("El modo lectura no está disponible en esta página", isPresented: $readerFailed) {
            Button("Aceptar", role: .cancel) {}
        }
    }

    /// Light or dark window chrome to match the page, only when it differs from the phone's
    /// setting, and never while Pestañas y espacios is open on top.
    private var windowStyle: UIUserInterfaceStyle {
        guard !showTabs else { return .unspecified }
        let pageIsDark = PageColor.isDark(topColor)
        return pageIsDark == store.systemIsDark ? .unspecified : (pageIsDark ? .dark : .light)
    }

    /// The page's top color, frosted towards the top of the screen so the clock area
    /// blends in instead of looking like a flat band.
    private var statusBarBackground: some View {
        Color(uiColor: topColor)
            .overlay {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .opacity(0.6)
            }
    }

    /// Full floating toolbar, or a slim address line in the home-indicator strip.
    private var bottomBar: some View {
        Group {
            if collapsed {
                compactBar
                    .transition(.opacity)
            } else {
                toolbar
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, PageColor.isDark(bottomColor) ? .dark : .light)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: collapsed)
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

    /// Slim address line shown while scrolling down; tap to bring the toolbar back.
    private var compactBar: some View {
        Button {
            controller.setToolbarCollapsed(false)
        } label: {
            HStack(spacing: 4) {
                if controller.isPrivate {
                    Image(systemName: "eye.slash").foregroundStyle(Color.indigo)
                }
                Image(systemName: controller.url?.scheme == "https" ? "lock.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(controller.url?.scheme == "https" ? Color.secondary : Color.orange)
                Text(controller.url?.displayHost ?? "")
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mostrar barra: \(controller.url?.displayHost ?? "")")
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            if isEditing {
                editingField
            } else {
                ToolbarIcon(symbol: "arrow.left", label: "Atrás") {
                    if controller.canGoBack { controller.webView.goBack() } else { store.goHome() }
                }
                ToolbarIcon(symbol: "arrow.right", label: "Adelante", isEnabled: controller.canGoForward) {
                    controller.webView.goForward()
                }
                addressPill
                ToolbarIcon(symbol: "square.on.square", label: "Pestañas") {
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
                Label("Privado", systemImage: "eye.slash")
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
            .accessibilityLabel(shieldsUp ? "Shields activado, \(controller.blockedItems.count) bloqueados" : "Shields desactivado")

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
            .accessibilityLabel("Dirección: \(controller.url?.displayHost ?? "")")

            if controller.isReaderActive {
                Button { showReaderSettings = true } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.neutrinBlue)
                        .frame(width: 32, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Ajustes de texto")
            } else if controller.isReaderAvailable {
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
                .accessibilityLabel("Modo lectura")
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 32, height: 40)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(Color(.systemBackground).opacity(0.55), in: Capsule())
        .animation(.snappy, value: controller.isReaderAvailable)
        .animation(.snappy, value: controller.isReaderActive)
    }

    private var editingField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
            TextField("Busca o escribe una dirección", text: $addressText)
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
                // Select the whole address so typing replaces it.
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                    guard let field = note.object as? UITextField else { return }
                    DispatchQueue.main.async { field.selectAll(nil) }
                }
            if !addressText.isEmpty {
                Button { addressText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Borrar")
            }
            Button("Cancelar") { isEditing = false }
                .font(.subheadline.weight(.semibold))
                .padding(.trailing, 10)
        }
        .frame(height: 40)
    }

    private var moreMenu: some View {
        Menu {
            Button { controller.reloadOrStop() } label: {
                Label(controller.isLoading ? "Detener" : "Recargar",
                      systemImage: controller.isLoading ? "xmark" : "arrow.clockwise")
            }
            if let url = controller.url {
                let shareURL = LinkCleaner.cleaned(url)
                ShareLink(item: shareURL) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                let favorite = store.isFavorite(shareURL)
                Button { store.toggleFavorite(title: controller.title, url: url) } label: {
                    Label(favorite ? "Quitar de favoritos" : "Añadir a favoritos",
                          systemImage: favorite ? "star.slash" : "star")
                }
                Button { UIPasteboard.general.url = shareURL } label: {
                    Label("Copiar enlace", systemImage: "link")
                }
            }
            if controller.isReaderActive {
                Button { controller.exitReader() } label: {
                    Label("Salir del modo lectura", systemImage: "doc.plaintext.fill")
                }
                Button { showReaderSettings = true } label: {
                    Label("Ajustes de texto", systemImage: "textformat.size")
                }
            } else if controller.isReaderAvailable {
                Button(action: openReader) {
                    Label("Modo lectura", systemImage: "doc.plaintext")
                }
            }
            Picker(selection: $store.privacySettings.websiteDarkMode) {
                ForEach(WebsiteDarkMode.allCases) { mode in
                    Text(mode.name).tag(mode)
                }
            } label: {
                Label("Modo oscuro en sitios web", systemImage: "moon")
            }
            .pickerStyle(.menu)
            Divider()
            Button { store.newTab(isPrivate: controller.isPrivate) } label: {
                Label(controller.isPrivate ? "Nueva pestaña privada" : "Nueva pestaña", systemImage: "plus.square.on.square")
            }
            if !controller.isPrivate {
                Button { store.newTab(isPrivate: true) } label: {
                    Label("Nueva pestaña privada", systemImage: "eye.slash")
                }
            }
            Button { store.goHome() } label: {
                Label("Página de inicio", systemImage: "house")
            }
            Button { showSettings = true } label: {
                Label("Ajustes", systemImage: "gearshape")
            }
            Button(role: .destructive) { store.close(controller.id) } label: {
                Label("Cerrar pestaña", systemImage: "xmark.square")
            }
        } label: {
            ToolbarIconLabel(symbol: "ellipsis")
        }
        .accessibilityLabel("Más")
    }

    private func openReader() {
        guard !isOpeningReader else { return }
        isOpeningReader = true
        Task {
            let article = await controller.extractArticle()
            isOpeningReader = false
            if let article {
                controller.showReader(article, settings: store.readerSettings)
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

/// Sets the window's light/dark style (this is what colors the clock and battery).
private struct WindowAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let style = style
        DispatchQueue.main.async {
            if view.window?.overrideUserInterfaceStyle != style {
                view.window?.overrideUserInterfaceStyle = style
            }
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        view.window?.overrideUserInterfaceStyle = .unspecified
    }
}
