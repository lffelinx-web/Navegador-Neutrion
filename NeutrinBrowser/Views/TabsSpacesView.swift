import SwiftUI

/// "Pestañas y espacios": switch spaces, browse tabs as cards, manage spaces.
struct TabsSpacesView: View {
    @EnvironmentObject private var store: BrowserStore
    /// Closes the screen (it's shown as an overlay so the page stays visible behind it).
    var onClose: () -> Void

    @Namespace private var modeNamespace
    @State private var dragOffset: CGFloat = 0

    @State private var mode: Mode = .tabs
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var showNewSpace = false
    @State private var editingSpace: BrowserSpace?
    @State private var spacePendingDeletion: BrowserSpace?

    private enum Mode { case tabs, privateTabs, spaces }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch mode {
                    case .tabs:
                        spacesStrip
                        tabsSection
                    case .privateTabs:
                        privateSection
                    case .spaces:
                        spacesManager
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            // Title and the Tabs/Private/Spaces island float above the content.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 12) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 40, height: 5)
                        .accessibilityHidden(true)
                    header
                    modePicker
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .contentShape(Rectangle())
                // Swipe down on the top area to close, like a sheet.
                .gesture(closeGesture)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0.65), .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                        .ignoresSafeArea(edges: .top)
                }
            }

            bottomBar
        }
        .offset(y: dragOffset)
        .sheet(isPresented: $showNewSpace) {
            SpaceEditorView(space: nil).environmentObject(store)
        }
        .sheet(item: $editingSpace) { space in
            SpaceEditorView(space: space).environmentObject(store)
        }
        .onAppear {
            // Opened from a private tab, start on the Private section.
            if store.isPrivateBrowsing { mode = .privateTabs }
        }
        .confirmationDialog(
            "¿Eliminar «\(spacePendingDeletion?.name ?? "")»?",
            isPresented: Binding(get: { spacePendingDeletion != nil }, set: { if !$0 { spacePendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Eliminar el espacio y sus pestañas", role: .destructive) {
                if let space = spacePendingDeletion {
                    withAnimation { store.deleteSpace(space.id) }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Pestañas y espacios")
                .font(.system(size: 28, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Menu {
                Button { onClose() } label: { Label("Listo", systemImage: "checkmark") }
                Button(role: .destructive) {
                    withAnimation { store.closeAllTabs(in: store.activeSpaceID) }
                } label: {
                    Label("Close All Tabs in \(store.activeSpace?.name ?? "Espacio")", systemImage: "xmark.square")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .glass(cornerRadius: 21, interactive: true)
            }
            .accessibilityLabel("Más")
        }
    }

    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 320 {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
                }
            }
    }

    /// Floating island with a glass "droplet" that slides to the selected option.
    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton(.tabs, title: "Pestañas", symbol: "square.on.square")
            modeButton(.privateTabs, title: "Privado", symbol: "eye.slash")
            modeButton(.spaces, title: "Espacios", symbol: "square.stack.3d.up")
        }
        .padding(4)
        .glass(cornerRadius: 24)
    }

    private func modeButton(_ value: Mode, title: String, symbol: String) -> some View {
        let selected = mode == value
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { mode = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.neutrinBlue : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if selected {
                        SelectionDroplet()
                            .matchedGeometryEffect(id: "droplet", in: modeNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tabs mode

    private var spacesStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Espacios", actionTitle: "Gestionar") {
                withAnimation(.snappy) { mode = .spaces }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.spaces) { space in
                        SpaceCard(
                            space: space,
                            tabCount: store.tabs(in: space.id).count,
                            isSelected: space.id == store.activeSpaceID
                        ) {
                            withAnimation(.snappy) { store.selectSpace(space.id) }
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        }
    }

    private var visibleTabs: [TabRecord] {
        let tabs = store.tabs(in: store.activeSpaceID)
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return tabs }
        return tabs.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(term)
                || ($0.url?.absoluteString.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    private var tabsSection: some View {
        let count = store.tabs(in: store.activeSpaceID).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.activeSpace?.name ?? "Pestañas").font(.title3.weight(.bold))
                Text("· \(count) \(count == 1 ? "pestaña" : "pestañas")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.snappy) {
                        isSearching.toggle()
                        if !isSearching { searchText = "" }
                    }
                } label: {
                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(isSearching ? "Dejar de buscar" : "Buscar pestañas")
            }

            if isSearching {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar pestañas", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .card(cornerRadius: 22)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(visibleTabs) { tab in
                    TabCard(
                        tab: tab,
                        snapshot: store.snapshots[tab.id],
                        isActive: tab.id == store.activeTabID,
                        onSelect: {
                            store.select(tab.id)
                            onClose()
                        },
                        onClose: {
                            withAnimation(.snappy) { store.close(tab.id) }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Private mode

    private var privateSection: some View {
        let tabs = store.privateTabs
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Privado").font(.title3.weight(.bold))
                Text("· \(tabs.count) \(tabs.count == 1 ? "pestaña" : "pestañas")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !tabs.isEmpty {
                    Button("Cerrar todas", role: .destructive) {
                        withAnimation(.snappy) { store.closeAllPrivateTabs() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if tabs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.indigo)
                    Text("Navega en privado")
                        .font(.headline)
                    Text("Las pestañas privadas no guardan historial, y sus cookies y datos se borran al cerrarlas. Shields sigue activo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .card(cornerRadius: 22)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(tabs) { tab in
                        TabCard(
                            tab: tab,
                            snapshot: store.snapshots[tab.id],
                            isActive: tab.id == store.activeTabID,
                            onSelect: {
                                store.select(tab.id)
                                onClose()
                            },
                            onClose: {
                                withAnimation(.snappy) { store.close(tab.id) }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Spaces mode

    private var spacesManager: some View {
        VStack(spacing: 10) {
            ForEach(store.spaces) { space in
                let count = store.tabs(in: space.id).count
                let isActive = space.id == store.activeSpaceID
                HStack(spacing: 14) {
                    Image(systemName: space.symbol)
                        .font(.title3)
                        .foregroundStyle(Color.neutrinBlue)
                        .frame(width: 46, height: 46)
                        .background(Color.neutrinBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(space.name).font(.headline)
                        Text("\(count) \(count == 1 ? "pestaña" : "pestañas")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.neutrinBlue)
                    }
                    Menu {
                        Button { editingSpace = space } label: { Label("Editar", systemImage: "pencil") }
                        Button(role: .destructive) {
                            withAnimation { store.closeAllTabs(in: space.id) }
                        } label: {
                            Label("Cerrar todas las pestañas", systemImage: "xmark.square")
                        }
                        if store.spaces.count > 1 {
                            Button(role: .destructive) { spacePendingDeletion = space } label: {
                                Label("Eliminar espacio", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                }
                .padding(14)
                .card(cornerRadius: 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) {
                        store.selectSpace(space.id)
                        mode = .tabs
                    }
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                store.newTab(isPrivate: mode == .privateTabs)
                onClose()
            } label: {
                Label(mode == .privateTabs ? "Nueva pestaña privada" : "Nueva pestaña", systemImage: "plus")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            if mode != .privateTabs {
                Divider().frame(height: 24)
                Button { showNewSpace = true } label: {
                    Label("Nuevo espacio", systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
            }
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(mode == .privateTabs ? Color.indigo : Color.neutrinBlue)
        .frame(height: 56)
        .glass(cornerRadius: 28)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

private struct SpaceCard: View {
    let space: BrowserSpace
    let tabCount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: space.symbol).font(.system(size: 18))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.neutrinBlue)
                    }
                }
                Spacer(minLength: 6)
                Text(space.name).font(.subheadline.weight(.bold)).lineLimit(1)
                Text("\(tabCount) \(tabCount == 1 ? "pestaña" : "pestañas")")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.neutrinBlue : .secondary)
            }
            .padding(12)
            .frame(width: 116, height: 92, alignment: .leading)
            .background(isSelected ? Color.neutrinBlue.opacity(0.10) : .clear,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .card(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.neutrinBlue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TabCard: View {
    let tab: TabRecord
    let snapshot: UIImage?
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 24, height: 24)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityLabel("Cerrar \(tab.displayTitle)")
                }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: tab.url == nil ? "house" : "doc.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.displayTitle)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                    Text(tab.url?.displayHost ?? "Página de inicio")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 52, alignment: .top)
            .padding(.horizontal, 6)
            .padding(.top, 10)
        }
        .padding(6)
        .card(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isActive ? Color.neutrinBlue : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var preview: some View {
        if let snapshot {
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else if tab.url == nil {
            ZStack {
                LinearGradient(colors: [Color(red: 0.95, green: 0.96, blue: 0.99), Color(red: 0.84, green: 0.89, blue: 0.97)],
                               startPoint: .top, endPoint: .bottom)
                NeutrinLogo().frame(width: 46)
            }
        } else {
            ArtworkView(artwork: .forID(tab.id))
        }
    }
}

/// The selected segment: a liquid-glass drop on iOS 26, a tinted capsule before.
private struct SelectionDroplet: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(Color.neutrinBlue.opacity(0.12))
                .glassEffect(.regular.tint(Color.neutrinBlue.opacity(0.18)).interactive(), in: Capsule())
        } else {
            Capsule().fill(Color.neutrinBlue.opacity(0.16))
        }
    }
}
