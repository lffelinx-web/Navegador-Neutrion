import SwiftUI

/// The start page: logo, search, shortcuts, favorites and recent pages.
struct HomeView: View {
    @EnvironmentObject private var store: BrowserStore
    @Binding var showTabs: Bool

    @State private var query = ""
    @State private var sheet: HomeSheet?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    searchBar
                    quickActions
                    favoritesSection
                    recentSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)

            if !searchFocused {
                spaceBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: searchFocused)
        .sheet(item: $sheet) { item in
            sheetContent(item)
                .environmentObject(store)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button { sheet = .settings } label: {
                    Image(systemName: "person")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .glass(cornerRadius: 21)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            NeutrinLogo()
                .frame(width: 86)
            (Text("Neutrin").fontWeight(.bold) + Text(" Browser").fontWeight(.regular))
                .font(.system(size: 28, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search or enter an address", text: $query)
                .focused($searchFocused)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(submit)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Clear")
            }
            Button { sheet = .scanner } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.neutrinBlue)
            }
            .accessibilityLabel("Scan QR code")
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .glass(cornerRadius: 27)
    }

    private var quickActions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 18) {
            ForEach(QuickAction.allCases) { action in
                Button { perform(action) } label: {
                    VStack(spacing: 7) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 21))
                            .foregroundStyle(action == .explore ? Color.neutrinBlue : Color.primary)
                            .frame(width: 56, height: 56)
                            .background(action == .explore ? Color.neutrinBlue.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .glass(cornerRadius: 17)
                        Text(action.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Favorites") { sheet = .favorites }
            Group {
                if store.favorites.isEmpty {
                    Button { sheet = .addFavorite } label: {
                        Label("Add your first favorite", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(store.favorites) { favorite in
                                FavoriteCard(favorite: favorite) { store.open(favorite.url) }
                                    .contextMenu {
                                        Button { store.open(favorite.url, inNewTab: true) } label: {
                                            Label("Open in New Tab", systemImage: "plus.square.on.square")
                                        }
                                        Button(role: .destructive) { store.removeFavorite(favorite) } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .glass(cornerRadius: 22)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent") { sheet = .history }
            VStack(spacing: 0) {
                if store.history.isEmpty {
                    Text("Pages you visit will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    let recent = Array(store.history.prefix(4))
                    ForEach(recent) { entry in
                        Button { store.open(entry.url) } label: {
                            HistoryRow(entry: entry)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if entry.id != recent.last?.id {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
            }
            .glass(cornerRadius: 22)
        }
    }

    private var spaceBar: some View {
        let count = store.tabs(in: store.activeSpaceID).count
        return Button {
            store.captureActiveSnapshot()
            showTabs = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: store.activeSpace?.symbol ?? "square.on.square")
                Text(store.activeSpace?.name ?? "Tabs")
                Text("· \(count) \(count == 1 ? "tab" : "tabs")").foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .frame(height: 48)
            .glass(cornerRadius: 24)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .accessibilityLabel("Show tabs and spaces")
    }

    // MARK: - Actions

    private func submit() {
        let text = query
        query = ""
        searchFocused = false
        store.open(text)
    }

    private func perform(_ action: QuickAction) {
        switch action {
        case .favorites: sheet = .favorites
        case .read: sheet = .history
        case .tools: sheet = .settings
        case .add: sheet = .addFavorite
        case .apps:
            store.captureActiveSnapshot()
            showTabs = true
        case .explore, .watch, .images:
            if let url = action.url { store.open(url) }
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: HomeSheet) -> some View {
        switch item {
        case .favorites:
            FavoritesView { url in sheet = nil; store.open(url) }
        case .history:
            HistoryView { url in sheet = nil; store.open(url) }
        case .settings:
            SettingsView()
        case .addFavorite:
            AddFavoriteView()
        case .scanner:
            ScannerSheet { value in sheet = nil; store.open(value) }
        }
    }
}

private enum HomeSheet: Identifiable {
    case favorites, history, settings, addFavorite, scanner
    var id: Self { self }
}

private enum QuickAction: CaseIterable, Identifiable {
    case explore, favorites, read, watch, images, tools, apps, add
    var id: Self { self }

    var title: String {
        switch self {
        case .explore: "Explore"
        case .favorites: "Favorites"
        case .read: "Read"
        case .watch: "Watch"
        case .images: "Images"
        case .tools: "Tools"
        case .apps: "Apps"
        case .add: "Add"
        }
    }

    var symbol: String {
        switch self {
        case .explore: "leaf"
        case .favorites: "star"
        case .read: "book"
        case .watch: "play"
        case .images: "photo"
        case .tools: "cube"
        case .apps: "square.grid.2x2"
        case .add: "plus"
        }
    }

    var url: URL? {
        switch self {
        case .explore: URL(string: "https://news.google.com")
        case .watch: URL(string: "https://www.youtube.com")
        case .images: URL(string: "https://unsplash.com")
        default: nil
        }
    }
}

struct FavoriteCard: View {
    let favorite: Favorite
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ArtworkView(artwork: favorite.artwork)
                    .frame(width: 96, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(favorite.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(width: 96)
            }
        }
        .buttonStyle(.plain)
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(entry.url.displayHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
