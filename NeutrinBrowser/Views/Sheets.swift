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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        NeutrinLogo().frame(width: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Neutrin Browser").font(.headline)
                            Text("A calmer, more open web.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Search Engine") {
                    Picker("Search Engine", selection: $store.searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.name).tag(engine)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Privacy") {
                    Button("Clear History", role: .destructive) {
                        store.clearHistory()
                        message = "History cleared."
                    }
                    Button("Clear Cookies and Website Data", role: .destructive) {
                        store.clearWebsiteData()
                        message = "Website data cleared."
                    }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
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
