import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    let onOpen: (URL) -> Void
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 14)], spacing: 18) {
                    ForEach(store.favorites) { favorite in
                        FavoriteCard(favorite: favorite) { onOpen(favorite.url) }
                            .contextMenu {
                                Button(role: .destructive) { store.removeFavorite(favorite) } label: {
                                    Label("Quitar", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(20)
            }
            .overlay {
                if store.favorites.isEmpty {
                    ContentUnavailableView("Sin favoritos", systemImage: "star",
                                           description: Text("Añade tus páginas preferidas para abrirlas con un toque."))
                }
            }
            .navigationTitle("Favoritos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Listo") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Añadir favorito")
                }
            }
            .sheet(isPresented: $showAdd) { AddFavoriteView().environmentObject(store) }
        }
    }
}

struct AddFavoriteView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var address = ""
    @State private var artwork: Artwork = .mountains

    private var resolvedURL: URL? {
        URLResolver.resolve(address, engine: store.searchEngine)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $title)
                    TextField("Dirección", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Portada") {
                    HStack(spacing: 12) {
                        ForEach(Artwork.allCases) { item in
                            Button { artwork = item } label: {
                                ArtworkView(artwork: item)
                                    .frame(height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(artwork == item ? Color.neutrinBlue : .clear, lineWidth: 3)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.name)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Añadir favorito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let url = resolvedURL else { return }
                        let name = title.trimmingCharacters(in: .whitespaces)
                        store.addFavorite(title: name.isEmpty ? url.displayHost : name, url: url, artwork: artwork)
                        dismiss()
                    }
                    .disabled(resolvedURL == nil)
                }
            }
            .onAppear {
                // Prefill with the page open in the active tab, if any.
                if address.isEmpty, let tab = store.activeTab, let url = tab.url {
                    address = url.absoluteString
                    title = tab.title
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    let onOpen: (URL) -> Void
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.history) { entry in
                    Button { onOpen(entry.url) } label: { HistoryRow(entry: entry) }
                        .buttonStyle(.plain)
                }
                .onDelete(perform: store.removeHistory)
            }
            .overlay {
                if store.history.isEmpty {
                    ContentUnavailableView("Sin páginas recientes", systemImage: "clock",
                                           description: Text("Las páginas que visites aparecerán aquí."))
                }
            }
            .navigationTitle("Recientes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Listo") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Borrar", role: .destructive) { confirmClear = true }
                        .disabled(store.history.isEmpty)
                }
            }
            .confirmationDialog("¿Borrar todas las páginas recientes?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Borrar historial", role: .destructive) { store.clearHistory() }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var confirmClearData = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        NeutrinLogo().frame(width: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Neutrin Browser").font(.headline)
                            Text("Una web más tranquila y privada.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    HStack(spacing: 12) {
                        StatCell(value: store.stats.trackers, title: "Rastreadores")
                        StatCell(value: store.stats.ads, title: "Anuncios")
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    Toggle("Bloquear anuncios", isOn: $store.privacySettings.blockAds)
                    Toggle("Ocultar huecos de anuncios", isOn: $store.privacySettings.hideAdPlaceholders)
                        .disabled(!store.privacySettings.blockAds)
                    Toggle("Bloquear rastreadores", isOn: $store.privacySettings.blockTrackers)
                    NavigationLink {
                        FilterListsView(manager: store.filterLists)
                    } label: {
                        LabeledContent("Listas de filtros", value: "EasyList, EasyPrivacy")
                    }
                } header: {
                    Text("Shields")
                } footer: {
                    Text("Bloqueando desde el \(store.stats.since.formatted(date: .abbreviated, time: .omitted)). Neutrin bloquea servicios conocidos de anuncios y rastreo antes de que carguen, así las páginas van más rápido y las empresas no pueden seguirte de un sitio a otro.")
                }

                Section {
                    Toggle("Quitar rastreo de los enlaces", isOn: $store.privacySettings.removeTrackingParameters)
                    Toggle("Global Privacy Control", isOn: $store.privacySettings.globalPrivacyControl)
                    Toggle("Cambiar a HTTPS", isOn: $store.privacySettings.upgradeToHTTPS)
                    NavigationLink {
                        ShieldsExceptionsView()
                    } label: {
                        LabeledContent("Sitios sin Shields", value: "\(store.shieldsDownHosts.count)")
                    }
                } header: {
                    Text("Privacidad")
                } footer: {
                    Text("Quita utm_, fbclid, gclid y etiquetas similares de los enlaces. Global Privacy Control pide a los sitios que no vendan ni compartan tus datos. El cambio a HTTPS se aplica a las pestañas nuevas.")
                }

                Section("Buscador") {
                    Picker("Buscador", selection: $store.searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            HStack {
                                Text(engine.name)
                                if engine.isPrivate {
                                    Text("Privado")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Color.neutrinBlue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.neutrinBlue.opacity(0.12), in: Capsule())
                                }
                            }
                            .tag(engine)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Picker("Modo oscuro en sitios web", selection: $store.privacySettings.websiteDarkMode) {
                        ForEach(WebsiteDarkMode.allCases) { mode in
                            Text(mode.name).tag(mode)
                        }
                    }
                } header: {
                    Text("Apariencia")
                } footer: {
                    Text("Muestra los sitios claros con colores oscuros. Los sitios que ya tienen diseño oscuro se quedan como están.")
                }

                Section {
                    Picker("Fuente de lectura", selection: $store.readerSettings.font) {
                        ForEach(ReaderFont.allCases) { font in Text(font.name).tag(font) }
                    }
                    Picker("Tema de lectura", selection: $store.readerSettings.theme) {
                        ForEach(ReaderTheme.allCases) { theme in Text(theme.name).tag(theme) }
                    }
                    Stepper("Tamaño del texto: \(Int(store.readerSettings.fontSize))",
                            value: $store.readerSettings.fontSize,
                            in: ReaderSettings.fontSizeRange)
                } header: {
                    Text("Modo lectura")
                } footer: {
                    Text("Toca el icono de página en la barra de direcciones para leer artículos sin anuncios, ventanas emergentes ni distracciones.")
                }

                Section("Datos") {
                    Button("Borrar historial", role: .destructive) {
                        store.clearHistory()
                        message = "Historial borrado."
                    }
                    Button("Borrar cookies y datos de sitios", role: .destructive) {
                        confirmClearData = true
                    }
                    Button("Reiniciar estadísticas de Shields") {
                        store.resetStats()
                        message = "Estadísticas reiniciadas."
                    }
                }

                Section {
                    LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Motor de lectura", value: "Mozilla Readability")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .confirmationDialog("Se cerrará tu sesión en los sitios web.", isPresented: $confirmClearData, titleVisibility: .visible) {
                Button("Borrar cookies y datos", role: .destructive) {
                    store.clearWebsiteData()
                    message = "Datos de sitios borrados."
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("Aceptar", role: .cancel) {}
            }
        }
    }
}

private struct StatCell: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient.neutrin)
            Text("\(title) bloqueados")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct FilterListsView: View {
    @ObservedObject var manager: FilterListManager

    var body: some View {
        List {
            Section {
                ForEach(FilterListManager.sources) { source in
                    FilterListRow(source: source, manager: manager)
                }
            } footer: {
                Text("La lista propia de Neutrin siempre funciona sin conexión. Estas listas comunitarias añaden decenas de miles de reglas y se actualizan solas cada pocos días. EasyList y EasyPrivacy las mantienen los autores de EasyList (easylist.to).")
            }

            Section {
                Button {
                    Task { await manager.updateAll() }
                } label: {
                    HStack {
                        Text("Actualizar ahora")
                        Spacer()
                        if !manager.updating.isEmpty { ProgressView() }
                    }
                }
                .disabled(!manager.updating.isEmpty)
            }
        }
        .navigationTitle("Listas de filtros")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FilterListRow: View {
    let source: FilterListManager.Source
    @ObservedObject var manager: FilterListManager

    var body: some View {
        let sub = manager.subscription(source.id)
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { sub.isEnabled }, set: { manager.setEnabled($0, for: source.id) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name).font(.body.weight(.semibold))
                    Text(source.summary).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Group {
                if manager.updating.contains(source.id) {
                    Label("Actualizando…", systemImage: "arrow.down.circle")
                } else if let error = sub.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if let updated = sub.lastUpdated {
                    Label("\((sub.networkRuleCount + sub.cosmeticRuleCount).formatted()) reglas · actualizada \(updated.formatted(.relative(presentation: .named)))",
                          systemImage: "checkmark.circle")
                } else if sub.isEnabled {
                    Label("Pendiente de descarga", systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ShieldsExceptionsView: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        let hosts = store.shieldsDownHosts.sorted()
        List {
            ForEach(hosts, id: \.self) { host in
                Label(host, systemImage: "shield.slash")
            }
            .onDelete { offsets in
                store.restoreShields(forHosts: offsets.map { hosts[$0] })
            }
        }
        .overlay {
            if hosts.isEmpty {
                ContentUnavailableView("Shields está activo en todos los sitios", systemImage: "shield.lefthalf.filled",
                                       description: Text("Aquí aparecerán los sitios donde apagues Shields."))
            }
        }
        .navigationTitle("Shields desactivado")
        .toolbar { EditButton() }
    }
}

struct SpaceEditorView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    let space: BrowserSpace?
    @State private var name: String
    @State private var symbol: String

    private static let symbols = [
        "person", "briefcase", "graduationcap", "house", "cart", "airplane",
        "gamecontroller", "paintpalette", "book", "heart", "leaf", "star",
        "folder", "music.note", "film", "dumbbell", "fork.knife", "globe",
    ]

    init(space: BrowserSpace?) {
        self.space = space
        _name = State(initialValue: space?.name ?? "")
        _symbol = State(initialValue: space?.symbol ?? "folder")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Nombre del espacio", text: $name)
                }
                Section("Icono") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { item in
                            let selected = item == symbol
                            Button { symbol = item } label: {
                                Image(systemName: item)
                                    .font(.title3)
                                    .foregroundStyle(selected ? Color.neutrinBlue : Color.primary)
                                    .frame(width: 44, height: 44)
                                    .background(selected ? Color.neutrinBlue.opacity(0.18) : Color.primary.opacity(0.05),
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(space == nil ? "Nuevo espacio" : "Editar espacio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(space == nil ? "Crear" : "Guardar") {
                        if var existing = space {
                            existing.name = trimmedName
                            existing.symbol = symbol
                            store.updateSpace(existing)
                        } else {
                            store.addSpace(name: trimmedName, symbol: symbol)
                        }
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
