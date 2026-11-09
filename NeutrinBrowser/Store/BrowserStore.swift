import SwiftUI
import Combine
import WebKit

/// App state: spaces, tabs, favorites, history and privacy settings. Saved to disk as JSON.
/// Private tabs live only in memory.
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

    @Published var privacySettings: PrivacySettings {
        didSet { privacySettingsChanged(from: oldValue) }
    }
    @Published var readerSettings: ReaderSettings
    @Published private(set) var stats: BlockStats
    /// Sites where the user turned Shields off.
    @Published private(set) var shieldsDownHosts: Set<String>
    /// Set by the UI so "Match System" website dark mode can follow the phone.
    @Published private(set) var systemIsDark = false

    let contentBlocker = ContentBlocker()
    private var blockerTask: Task<Void, Never>?

    private var lastTabBySpace: [String: UUID]
    private var controllers: [UUID: TabController] = [:]
    private var cancellables: Set<AnyCancellable> = []

    private static let historyLimit = 300

    init() {
        let state = Self.loadState() ?? Self.defaultState()
        spaces = state.spaces
        tabs = state.tabs.filter { !$0.isPrivate }
        activeSpaceID = state.activeSpaceID
        activeTabID = state.activeTabID
        favorites = state.favorites
        history = state.history
        searchEngine = state.searchEngine
        lastTabBySpace = state.lastTabBySpace
        privacySettings = state.privacy ?? PrivacySettings()
        readerSettings = state.reader ?? ReaderSettings()
        stats = state.stats ?? BlockStats()
        shieldsDownHosts = Set(state.shieldsDownHosts ?? [])

        if !spaces.contains(where: { $0.id == activeSpaceID }), let first = spaces.first {
            activeSpaceID = first.id
        }
        if activeTab == nil || activeTab?.spaceID != activeSpaceID {
            selectSpace(activeSpaceID)
        }

        blockerTask = Task { [weak self] in
            guard let self else { return }
            await self.contentBlocker.prepare()
            self.refreshShields()
        }

        objectWillChange
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    // MARK: - Queries

    var activeTab: TabRecord? { tabs.first { $0.id == activeTabID } }
    var activeSpace: BrowserSpace? { spaces.first { $0.id == activeSpaceID } }
    var isPrivateBrowsing: Bool { activeTab?.isPrivate ?? false }

    /// Normal (non-private) tabs of a space.
    func tabs(in spaceID: UUID) -> [TabRecord] {
        tabs.filter { $0.spaceID == spaceID && !$0.isPrivate }
    }

    var privateTabs: [TabRecord] {
        tabs.filter(\.isPrivate)
    }

    func isFavorite(_ url: URL) -> Bool {
        favorites.contains { $0.url == url }
    }

    // MARK: - Shields

    var activeRuleLists: [WKContentRuleList] {
        contentBlocker.ruleLists(for: privacySettings)
    }

    var shieldsAreConfigured: Bool {
        privacySettings.blockAds || privacySettings.blockTrackers
    }

    func shieldsEnabled(for host: String?) -> Bool {
        guard let host = Self.normalizedHost(host) else { return true }
        return !shieldsDownHosts.contains(host)
    }

    func setShields(_ enabled: Bool, for host: String?) {
        guard let host = Self.normalizedHost(host) else { return }
        if enabled {
            shieldsDownHosts.remove(host)
        } else {
            shieldsDownHosts.insert(host)
        }
        // Reload open pages of that site so the change takes effect.
        for controller in controllers.values where Self.normalizedHost(controller.url?.host) == host {
            controller.applyShields(forHost: host)
            controller.webView.reload()
        }
    }

    func restoreShields(forHosts hosts: [String]) {
        shieldsDownHosts.subtract(hosts)
    }

    func resetStats() {
        stats = BlockStats()
    }

    var websiteDarkModeActive: Bool {
        switch privacySettings.websiteDarkMode {
        case .off: false
        case .always: true
        case .matchSystem: systemIsDark
        }
    }

    func updateSystemAppearance(isDark: Bool) {
        guard systemIsDark != isDark else { return }
        let before = websiteDarkModeActive
        systemIsDark = isDark
        if before != websiteDarkModeActive { refreshDarkMode() }
    }

    private func privacySettingsChanged(from old: PrivacySettings) {
        guard old != privacySettings else { return }
        controllers.values.forEach { $0.installUserScripts() }
        if old.websiteDarkMode != privacySettings.websiteDarkMode {
            refreshDarkMode()
        }
        if old.blockAds != privacySettings.blockAds
            || old.blockTrackers != privacySettings.blockTrackers
            || old.hideAdPlaceholders != privacySettings.hideAdPlaceholders {
            refreshShields()
        }
    }

    private func refreshShields() {
        controllers.values.forEach { $0.applyShields(forHost: $0.url?.host) }
    }

    private func refreshDarkMode() {
        let enabled = websiteDarkModeActive
        for controller in controllers.values {
            controller.installUserScripts()
            controller.setDarkMode(enabled)
        }
    }

    private func recordBlocked(_ items: [BlockedItem]) {
        for item in items {
            switch item.category {
            case .ads: stats.ads += 1
            case .trackers: stats.trackers += 1
            }
        }
    }

    /// Runs after the block lists are ready, so no page loads unprotected.
    private func whenShieldsReady(_ action: @escaping () -> Void) {
        if !contentBlocker.compiled.isEmpty || blockerTask == nil {
            action()
            return
        }
        let task = blockerTask
        Task {
            await task?.value
            action()
        }
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Tabs

    func controller(for tabID: UUID) -> TabController {
        if let existing = controllers[tabID] { return existing }

        let record = tabs.first { $0.id == tabID }
        let controller = TabController(id: tabID, isPrivate: record?.isPrivate ?? false, store: self)
        controller.onChange = { [weak self] changed in self?.controllerDidChange(changed) }
        controller.onVisit = { [weak self] visited in self?.recordVisit(visited) }
        controller.onSnapshot = { [weak self] id, image in self?.snapshots[id] = image }
        controller.onBlocked = { [weak self] items in self?.recordBlocked(items) }
        controllers[tabID] = controller

        if let url = record?.url {
            // Deferred so creating a controller during a view update doesn't publish changes.
            Task { @MainActor [weak self] in
                self?.whenShieldsReady { controller.load(url) }
            }
        }
        return controller
    }

    @discardableResult
    func newTab(url: URL? = nil, in spaceID: UUID? = nil, isPrivate: Bool = false) -> UUID {
        let record = TabRecord(spaceID: spaceID ?? activeSpaceID, url: url, isPrivate: isPrivate)
        tabs.append(record)
        select(record.id)
        return record.id
    }

    func select(_ tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        activeTabID = tabID
        guard !tab.isPrivate else { return }
        activeSpaceID = tab.spaceID
        lastTabBySpace[tab.spaceID.uuidString] = tabID
    }

    func close(_ tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let closed = tabs[index]
        let siblings = closed.isPrivate ? privateTabs : tabs(in: closed.spaceID)
        let position = siblings.firstIndex(where: { $0.id == tabID }) ?? 0
        tabs.remove(at: index)
        discardController(for: tabID)
        if closed.isPrivate && privateTabs.isEmpty { PrivateSession.end() }

        guard activeTabID == tabID else { return }
        let remaining = closed.isPrivate ? privateTabs : tabs(in: closed.spaceID)
        if !remaining.isEmpty {
            select(remaining[min(max(position - 1, 0), remaining.count - 1)].id)
        } else if closed.isPrivate {
            // Leaving private browsing: back to the last normal tab.
            selectSpace(activeSpaceID)
        } else {
            activeTabID = nil
            newTab(in: closed.spaceID)
        }
    }

    func closeAllTabs(in spaceID: UUID) {
        tabs(in: spaceID).forEach { discardController(for: $0.id) }
        tabs.removeAll { $0.spaceID == spaceID && !$0.isPrivate }
        if activeTab == nil {
            activeTabID = nil
            selectSpace(activeSpaceID)
        }
    }

    func closeAllPrivateTabs() {
        privateTabs.forEach { discardController(for: $0.id) }
        tabs.removeAll(where: \.isPrivate)
        PrivateSession.end()
        if activeTab == nil {
            activeTabID = nil
            selectSpace(activeSpaceID)
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
            newTab(url: url, isPrivate: isPrivateBrowsing)
            return
        }
        tabs[index].url = url
        if let controller = controllers[tabID] {
            whenShieldsReady { controller.load(url) }
        } else {
            _ = controller(for: tabID)
        }
    }

    /// Takes the active tab back to the start page.
    func goHome() {
        guard let tabID = activeTabID, let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].url = nil
        tabs[index].title = ""
        discardController(for: tabID)
    }

    func captureActiveSnapshot() {
        guard let tabID = activeTabID else { return }
        controllers[tabID]?.captureSnapshot()
    }

    private func discardController(for tabID: UUID) {
        controllers[tabID] = nil
        snapshots[tabID] = nil
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
        } else if let latest = spaceTabs.last {
            select(latest.id)
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
        tabs(in: spaceID).forEach { discardController(for: $0.id) }
        tabs.removeAll { $0.spaceID == spaceID && !$0.isPrivate }
        spaces.removeAll { $0.id == spaceID }
        lastTabBySpace[spaceID.uuidString] = nil
        if activeSpaceID == spaceID, let first = spaces.first {
            selectSpace(first.id)
        }
    }

    // MARK: - Favorites & history

    func addFavorite(title: String, url: URL, artwork: Artwork) {
        favorites.append(Favorite(title: title, url: LinkCleaner.cleaned(url), artwork: artwork))
    }

    func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
    }

    func toggleFavorite(title: String, url: URL) {
        let url = LinkCleaner.cleaned(url)
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
        guard !controller.isPrivate, let url = controller.url, url.isWebURL else { return }
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
        // Added later: optional so older saves still load.
        var privacy: PrivacySettings?
        var reader: ReaderSettings?
        var stats: BlockStats?
        var shieldsDownHosts: [String]?
    }

    private static var stateURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("neutrin-state.json")
    }

    /// Saves everything except private tabs.
    func save() {
        let savedActiveTab = isPrivateBrowsing ? lastTabBySpace[activeSpaceID.uuidString] : activeTabID
        let state = PersistedState(
            spaces: spaces, tabs: tabs.filter { !$0.isPrivate }, activeSpaceID: activeSpaceID,
            activeTabID: savedActiveTab, lastTabBySpace: lastTabBySpace, favorites: favorites,
            history: history, searchEngine: searchEngine, privacy: privacySettings, reader: readerSettings,
            stats: stats, shieldsDownHosts: shieldsDownHosts.sorted()
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.stateURL, options: [.atomic, .completeFileProtection])
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
            lastTabBySpace: [:], favorites: favorites, history: [], searchEngine: .duckDuckGo,
            privacy: PrivacySettings(), reader: ReaderSettings(), stats: BlockStats(), shieldsDownHosts: []
        )
    }
}
