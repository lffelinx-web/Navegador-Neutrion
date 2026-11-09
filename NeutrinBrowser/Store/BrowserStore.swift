import SwiftUI
import Combine
import WebKit

/// App state: spaces, tabs, favorites and history. Saved to disk as JSON.
@MainActor
final class BrowserStore: ObservableObject {
    @Published var spaces: [BrowserSpace]
    @Published var tabs: [TabRecord]
    @Published var activeSpaceID: UUID
    @Published var activeTabID: UUID?
    @Published var favorites: [Favorite]
    @Published var history: [HistoryEntry]
    @Published var searchEngine: SearchEngine
    @Published private(set) var snapshots: [UUID: UIImage] = [:]

    private var lastTabBySpace: [String: UUID]
    private var controllers: [UUID: TabController] = [:]
    private var saveCancellable: AnyCancellable?

    private static let historyLimit = 300

    init() {
        let state = Self.loadState() ?? Self.defaultState()
        spaces = state.spaces
        tabs = state.tabs
        activeSpaceID = state.activeSpaceID
        activeTabID = state.activeTabID
        favorites = state.favorites
        history = state.history
        searchEngine = state.searchEngine
        lastTabBySpace = state.lastTabBySpace

        if !spaces.contains(where: { $0.id == activeSpaceID }), let first = spaces.first {
            activeSpaceID = first.id
        }
        if activeTab == nil || activeTab?.spaceID != activeSpaceID {
            selectSpace(activeSpaceID)
        }

        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    // MARK: - Queries

    var activeTab: TabRecord? { tabs.first { $0.id == activeTabID } }
    var activeSpace: BrowserSpace? { spaces.first { $0.id == activeSpaceID } }

    func tabs(in spaceID: UUID) -> [TabRecord] {
        tabs.filter { $0.spaceID == spaceID }
    }

    func isFavorite(_ url: URL) -> Bool {
        favorites.contains { $0.url == url }
    }

    // MARK: - Tabs

    func controller(for tabID: UUID) -> TabController {
        if let existing = controllers[tabID] { return existing }

        let controller = TabController(id: tabID)
        controller.onChange = { [weak self] changed in self?.controllerDidChange(changed) }
        controller.onVisit = { [weak self] visited in self?.recordVisit(visited) }
        controller.onSnapshot = { [weak self] id, image in self?.snapshots[id] = image }
        controllers[tabID] = controller

        if let url = tabs.first(where: { $0.id == tabID })?.url {
            // Deferred so creating a controller during a view update doesn't publish changes.
            Task { @MainActor in controller.load(url) }
        }
        return controller
    }

    @discardableResult
    func newTab(url: URL? = nil, in spaceID: UUID? = nil) -> UUID {
        let record = TabRecord(spaceID: spaceID ?? activeSpaceID, url: url)
        tabs.append(record)
        select(record.id)
        return record.id
    }

    func select(_ tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        activeTabID = tabID
        activeSpaceID = tab.spaceID
        lastTabBySpace[tab.spaceID.uuidString] = tabID
    }

    func close(_ tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let spaceID = tabs[index].spaceID
        let position = tabs(in: spaceID).firstIndex(where: { $0.id == tabID }) ?? 0
        tabs.remove(at: index)
        controllers[tabID] = nil
        snapshots[tabID] = nil

        guard activeTabID == tabID else { return }
        let remaining = tabs(in: spaceID)
        if !remaining.isEmpty {
            let next = remaining[min(max(position - 1, 0), remaining.count - 1)]
            select(next.id)
        } else {
            activeTabID = nil
            newTab(in: spaceID)
        }
    }

    func closeAllTabs(in spaceID: UUID) {
        for tab in tabs(in: spaceID) {
            controllers[tab.id] = nil
            snapshots[tab.id] = nil
        }
        tabs.removeAll { $0.spaceID == spaceID }
        if spaceID == activeSpaceID {
            activeTabID = nil
            newTab(in: spaceID)
        }
    }

    /// Opens what the user typed (address or search) in the active tab.
    func open(_ input: String) {
        guard let url = URLResolver.resolve(input, engine: searchEngine) else { return }
        open(url)
    }

    func open(_ url: URL, inNewTab: Bool = false) {
        guard !inNewTab, let tabID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            newTab(url: url)
            return
        }
        tabs[index].url = url
        if let controller = controllers[tabID] {
            controller.load(url)
        } else {
            _ = controller(for: tabID)
        }
    }

    /// Takes the active tab back to the start page.
    func goHome() {
        guard let tabID = activeTabID, let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].url = nil
        tabs[index].title = ""
        controllers[tabID] = nil
        snapshots[tabID] = nil
    }

    func captureActiveSnapshot() {
        guard let tabID = activeTabID else { return }
        controllers[tabID]?.captureSnapshot()
    }

    private func controllerDidChange(_ controller: TabController) {
        guard let index = tabs.firstIndex(where: { $0.id == controller.id }) else { return }
        let url = controller.url ?? tabs[index].url
        if tabs[index].title != controller.title || tabs[index].url != url {
            tabs[index].title = controller.title
            tabs[index].url = url
        }
    }

    // MARK: - Spaces

    func selectSpace(_ spaceID: UUID) {
        activeSpaceID = spaceID
        let spaceTabs = tabs(in: spaceID)
        if let last = lastTabBySpace[spaceID.uuidString], spaceTabs.contains(where: { $0.id == last }) {
            select(last)
        } else if let first = spaceTabs.last {
            select(first.id)
        } else {
            newTab(in: spaceID)
        }
    }

    func addSpace(name: String, symbol: String) {
        let space = BrowserSpace(name: name, symbol: symbol)
        spaces.append(space)
        selectSpace(space.id)
    }

    func updateSpace(_ space: BrowserSpace) {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[index] = space
    }

    func deleteSpace(_ spaceID: UUID) {
        guard spaces.count > 1 else { return }
        for tab in tabs(in: spaceID) {
            controllers[tab.id] = nil
            snapshots[tab.id] = nil
        }
        tabs.removeAll { $0.spaceID == spaceID }
        spaces.removeAll { $0.id == spaceID }
        lastTabBySpace[spaceID.uuidString] = nil
        if activeSpaceID == spaceID, let first = spaces.first {
            selectSpace(first.id)
        }
    }

    // MARK: - Favorites & history

    func addFavorite(title: String, url: URL, artwork: Artwork) {
        favorites.append(Favorite(title: title, url: url, artwork: artwork))
    }

    func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
    }

    func toggleFavorite(title: String, url: URL) {
        if isFavorite(url) {
            favorites.removeAll { $0.url == url }
        } else {
            let name = title.isEmpty ? url.displayHost : title
            addFavorite(title: name, url: url, artwork: Artwork.allCases.randomElement() ?? .waves)
        }
    }

    func removeHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
    }

    func clearHistory() {
        history.removeAll()
    }

    func clearWebsiteData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }

    private func recordVisit(_ controller: TabController) {
        guard let url = controller.url, url.isWebURL else { return }
        if history.first?.url == url {
            history[0].title = controller.title
            history[0].visitedAt = Date()
            return
        }
        history.insert(HistoryEntry(title: controller.title, url: url), at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
    }

    // MARK: - Persistence

    private struct PersistedState: Codable {
        var spaces: [BrowserSpace]
        var tabs: [TabRecord]
        var activeSpaceID: UUID
        var activeTabID: UUID?
        var lastTabBySpace: [String: UUID]
        var favorites: [Favorite]
        var history: [HistoryEntry]
        var searchEngine: SearchEngine
    }

    private static var stateURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("neutrin-state.json")
    }

    func save() {
        let state = PersistedState(
            spaces: spaces, tabs: tabs, activeSpaceID: activeSpaceID, activeTabID: activeTabID,
            lastTabBySpace: lastTabBySpace, favorites: favorites, history: history, searchEngine: searchEngine
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }

    private static func loadState() -> PersistedState? {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data),
              !state.spaces.isEmpty else { return nil }
        return state
    }

    private static func defaultState() -> PersistedState {
        let personal = BrowserSpace(name: "Personal", symbol: "person")
        let work = BrowserSpace(name: "Trabajo", symbol: "briefcase")
        let study = BrowserSpace(name: "Estudio", symbol: "graduationcap")
        let favorites = [
            Favorite(title: "Design Ideas", url: URL(string: "https://dribbble.com")!, artwork: .mountains),
            Favorite(title: "Travel", url: URL(string: "https://www.lonelyplanet.com")!, artwork: .leaf),
            Favorite(title: "Reading", url: URL(string: "https://longreads.com")!, artwork: .waves),
        ]
        return PersistedState(
            spaces: [personal, work, study], tabs: [], activeSpaceID: personal.id, activeTabID: nil,
            lastTabBySpace: [:], favorites: favorites, history: [], searchEngine: .duckDuckGo
        )
    }
}
