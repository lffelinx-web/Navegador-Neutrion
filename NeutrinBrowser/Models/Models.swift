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

    var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.displayHost ?? "Start Page"
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

    /// Stable choice for a given identifier (UUID bytes don't change between launches).
    static func forID(_ id: UUID) -> Artwork {
        allCases[Int(id.uuid.0) % allCases.count]
    }
}

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case duckDuckGo, google, bing, ecosia
    var id: String { rawValue }

    var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        }
    }

    func searchURL(for query: String) -> URL? {
        let base: String
        switch self {
        case .duckDuckGo: base = "https://duckduckgo.com/"
        case .google: base = "https://www.google.com/search"
        case .bing: base = "https://www.bing.com/search"
        case .ecosia: base = "https://www.ecosia.org/search"
        }
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
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
        if looksLikeHost, let url = URL(string: "https://" + text), url.host != nil {
            return url
        }
        return engine.searchURL(for: text)
    }
}
