import Foundation

struct BrowserSpace: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
}

struct TabRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var spaceID: UUID
    /// `nil` means the tab shows the Neutrin start page.
    var url: URL?
    var title: String = ""
    var createdAt = Date()
    /// Private tabs keep no history or website data and are never saved to disk.
    var isPrivate = false

    init(id: UUID = UUID(), spaceID: UUID, url: URL? = nil, title: String = "", createdAt: Date = Date(), isPrivate: Bool = false) {
        self.id = id
        self.spaceID = spaceID
        self.url = url
        self.title = title
        self.createdAt = createdAt
        self.isPrivate = isPrivate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        spaceID = try container.decode(UUID.self, forKey: .spaceID)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.displayHost ?? "Página de inicio"
    }
}

struct Favorite: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
    var artwork: Artwork
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
    var visitedAt = Date()

    var displayTitle: String { title.isEmpty ? url.displayHost : title }
}

/// Built-in illustrations used for favorites and tabs without a snapshot.
enum Artwork: String, Codable, CaseIterable, Identifiable {
    case mountains, leaf, waves, sunset
    var id: String { rawValue }

    var name: String {
        switch self {
        case .mountains: "Montañas"
        case .leaf: "Hoja"
        case .waves: "Ondas"
        case .sunset: "Atardecer"
        }
    }

    /// Stable choice for a given identifier (UUID bytes don't change between launches).
    static func forID(_ id: UUID) -> Artwork {
        allCases[Int(id.uuid.0) % allCases.count]
    }
}

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case duckDuckGo, braveSearch, startpage, ecosia, google, bing
    var id: String { rawValue }

    var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .braveSearch: "Brave Search"
        case .startpage: "Startpage"
        case .ecosia: "Ecosia"
        case .google: "Google"
        case .bing: "Bing"
        }
    }

    /// Engines that don't build a profile of your searches.
    var isPrivate: Bool {
        switch self {
        case .duckDuckGo, .braveSearch, .startpage: true
        case .ecosia, .google, .bing: false
        }
    }

    func searchURL(for query: String) -> URL? {
        let base: String
        var parameter = "q"
        switch self {
        case .duckDuckGo: base = "https://duckduckgo.com/"
        case .braveSearch: base = "https://search.brave.com/search"
        case .startpage: base = "https://www.startpage.com/sp/search"; parameter = "query"
        case .ecosia: base = "https://www.ecosia.org/search"
        case .google: base = "https://www.google.com/search"
        case .bing: base = "https://www.bing.com/search"
        }
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: parameter, value: query)]
        return components?.url
    }
}

enum WebsiteDarkMode: String, Codable, CaseIterable, Identifiable {
    case off, matchSystem, always
    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Desactivado"
        case .matchSystem: "Igual que el sistema"
        case .always: "Siempre"
        }
    }
}

/// Shields and privacy options. Missing keys fall back to defaults so new options
/// can be added without losing saved settings.
struct PrivacySettings: Codable, Equatable {
    var blockAds = true
    var blockTrackers = true
    var hideAdPlaceholders = true
    var removeTrackingParameters = true
    var globalPrivacyControl = true
    var upgradeToHTTPS = true
    var websiteDarkMode: WebsiteDarkMode = .matchSystem

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PrivacySettings()
        blockAds = try c.decodeIfPresent(Bool.self, forKey: .blockAds) ?? defaults.blockAds
        blockTrackers = try c.decodeIfPresent(Bool.self, forKey: .blockTrackers) ?? defaults.blockTrackers
        hideAdPlaceholders = try c.decodeIfPresent(Bool.self, forKey: .hideAdPlaceholders) ?? defaults.hideAdPlaceholders
        removeTrackingParameters = try c.decodeIfPresent(Bool.self, forKey: .removeTrackingParameters) ?? defaults.removeTrackingParameters
        globalPrivacyControl = try c.decodeIfPresent(Bool.self, forKey: .globalPrivacyControl) ?? defaults.globalPrivacyControl
        upgradeToHTTPS = try c.decodeIfPresent(Bool.self, forKey: .upgradeToHTTPS) ?? defaults.upgradeToHTTPS
        websiteDarkMode = try c.decodeIfPresent(WebsiteDarkMode.self, forKey: .websiteDarkMode) ?? defaults.websiteDarkMode
    }
}

/// Running totals shown on the start page and in Settings.
struct BlockStats: Codable, Equatable {
    var ads = 0
    var trackers = 0
    var since = Date()

    var total: Int { ads + trackers }
}

struct BlockedItem: Hashable, Identifiable {
    let host: String
    let category: Blocklist.Category
    var id: String { category.rawValue + host }
}

extension URL {
    /// Host without a leading "www.", e.g. "article.space".
    var displayHost: String {
        guard let host else { return absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var isWebURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

enum URLResolver {
    /// Turns what the user typed into a URL: a full address, a bare domain, or a search.
    static func resolve(_ input: String, engine: SearchEngine) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), url.isWebURL, url.host != nil {
            return url
        }
        let looksLikeHost = !text.contains(" ") && (text.contains(".") || text.hasPrefix("localhost"))
        if looksLikeHost {
            let scheme = text.hasPrefix("localhost") ? "http://" : "https://"
            if let url = URL(string: scheme + text), url.host != nil { return url }
        }
        return engine.searchURL(for: text)
    }
}
