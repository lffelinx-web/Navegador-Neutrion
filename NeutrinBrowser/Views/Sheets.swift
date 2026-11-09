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
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(20)
            }
            .overlay {
                if store.favorites.isEmpty {
                    ContentUnavailableView("No Favorites", systemImage: "star",
                                           description: Text("Add pages you love to open them in one tap."))
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add favorite")
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
                    TextField("Title", text: $title)
                    TextField("Address", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Cover") {
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
                            .accessibilityLabel(item.rawValue.capitalized)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Add Favorite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
                    ContentUnavailableView("No Recent Pages", systemImage: "clock",
                                           description: Text("Pages you visit will appear here."))
                }
            }
            .navigationTitle("Recent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear", role: .destructive) { confirmClear = true }
                        .disabled(store.history.isEmpty)
                }
            }
            .confirmationDialog("Clear all recent pages?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { store.clearHistory() }
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
                            Text("A calmer, more private web.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    HStack(spacing: 12) {
                        StatCell(value: store.stats.trackers, title: "Trackers")
                        StatCell(value: store.stats.ads, title: "Ads")
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    Toggle("Block Ads", isOn: $store.privacySettings.blockAds)
                    Toggle("Hide Empty Ad Spaces", isOn: $store.privacySettings.hideAdPlaceholders)
                        .disabled(!store.privacySettings.blockAds)
                    Toggle("Block Trackers", isOn: $store.privacySettings.blockTrackers)
                } header: {
                    Text("Shields")
                } footer: {
                    Text("Blocked since \(store.stats.since.formatted(date: .abbreviated, time: .omitted)). Neutrin blocks known ad and tracking services before they load, so pages are faster and companies can't follow you from site to site.")
                }

                Section {
                    Toggle("Remove Tracking from Links", isOn: $store.privacySettings.removeTrackingParameters)
                    Toggle("Global Privacy Control", isOn: $store.privacySettings.globalPrivacyControl)
                    Toggle("Upgrade to HTTPS", isOn: $store.privacySettings.upgradeToHTTPS)
                    NavigationLink {
                        ShieldsExceptionsView()
                    } label: {
                        LabeledContent("Sites with Shields Down", value: "\(store.shieldsDownHosts.count)")
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Removes utm_, fbclid, gclid and similar tags from links. Global Privacy Control tells websites not to sell or share your data. HTTPS upgrades apply to new tabs.")
                }

                Section("Search Engine") {
                    Picker("Search Engine", selection: $store.searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            HStack {
                                Text(engine.name)
                                if engine.isPrivate {
                                    Text("Private")
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
                    Picker("Dark Mode for Websites", selection: $store.privacySettings.websiteDarkMode) {
                        ForEach(WebsiteDarkMode.allCases) { mode in
                            Text(mode.name).tag(mode)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Shows light websites in dark colors. Sites that already have a dark design are left as they are.")
                }

                Section {
                    Picker("Reader Font", selection: $store.readerSettings.font) {
                        ForEach(ReaderFont.allCases) { font in Text(font.name).tag(font) }
                    }
                    Picker("Reader Theme", selection: $store.readerSettings.theme) {
                        ForEach(ReaderTheme.allCases) { theme in Text(theme.name).tag(theme) }
                    }
                    Stepper("Text Size: \(Int(store.readerSettings.fontSize))",
                            value: $store.readerSettings.fontSize,
                            in: ReaderSettings.fontSizeRange)
                } header: {
                    Text("Reader Mode")
                } footer: {
                    Text("Tap the page icon in the address bar to read articles without ads, pop-ups or clutter.")
                }

                Section("Data") {
                    Button("Clear History", role: .destructive) {
                        store.clearHistory()
                        message = "History cleared."
                    }
                    Button("Clear Cookies and Website Data", role: .destructive) {
                        confirmClearData = true
                    }
                    Button("Reset Shields Statistics") {
                        store.resetStats()
                        message = "Statistics reset."
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Reader engine", value: "Mozilla Readability")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("You'll be signed out of websites.", isPresented: $confirmClearData, titleVisibility: .visible) {
                Button("Clear Cookies and Data", role: .destructive) {
                    store.clearWebsiteData()
                    message = "Website data cleared."
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
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
            Text("\(title) blocked")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                ContentUnavailableView("Shields Are Up Everywhere", systemImage: "shield.lefthalf.filled",
                                       description: Text("Sites where you turn Shields off will appear here."))
            }
        }
        .navigationTitle("Shields Down")
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
                Section("Name") {
                    TextField("Space name", text: $name)
                }
                Section("Icon") {
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
            .navigationTitle(space == nil ? "New Space" : "Edit Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(space == nil ? "Create" : "Save") {
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
