import Foundation
import WebKit

/// Downloads EasyList and EasyPrivacy, converts them to WebKit rules and keeps them up to date.
///
/// Compiled rule lists are cached by WebKit, so after the first download the
/// lists are ready instantly at launch. Updates are checked every few days.
@MainActor
final class FilterListManager: ObservableObject {
    struct Source: Identifiable {
        let id: String
        let name: String
        let summary: String
        let category: Blocklist.Category
        let urls: [URL]
    }

    struct Subscription: Codable, Equatable {
        var isEnabled = true
        var lastUpdated: Date?
        var lastChecked: Date?
        var networkRuleCount = 0
        var cosmeticRuleCount = 0
        var etag: String?
        var lastModified: String?
        var converterVersion: Int?
        var lastError: String?
    }

    static let sources: [Source] = [
        Source(
            id: "easylist", name: "EasyList",
            summary: "Blocks ads on websites around the world.",
            category: .ads,
            urls: [URL(string: "https://easylist.to/easylist/easylist.txt")!,
                   URL(string: "https://easylist-downloads.adblockplus.org/easylist.txt")!]
        ),
        Source(
            id: "easyprivacy", name: "EasyPrivacy",
            summary: "Blocks tracking scripts, pixels and analytics.",
            category: .trackers,
            urls: [URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
                   URL(string: "https://easylist-downloads.adblockplus.org/easyprivacy.txt")!]
        ),
    ]

    /// EasyList asks clients to refresh roughly every 4 days.
    static let updateInterval: TimeInterval = 4 * 24 * 60 * 60

    @Published private(set) var subscriptions: [String: Subscription] = [:]
    @Published private(set) var updating: Set<String> = []

    /// Called when compiled rules change, so open tabs can pick them up.
    var onRulesChanged: (() -> Void)?

    private var compiled: [String: WKContentRuleList] = [:]
    private var blockDomains: [String: Set<String>] = [:]
    private var exceptionDomains: [String: Set<String>] = [:]

    private enum Part: String { case network, cosmetic }

    init() {
        subscriptions = Self.loadState()
        for source in Self.sources where subscriptions[source.id] == nil {
            subscriptions[source.id] = Subscription()
        }
    }

    func subscription(_ id: String) -> Subscription {
        subscriptions[id] ?? Subscription()
    }

    // MARK: - Rules for web views

    func ruleLists(for settings: PrivacySettings) -> [WKContentRuleList] {
        var lists: [WKContentRuleList] = []
        for source in Self.sources where subscription(source.id).isEnabled {
            let wanted = source.category == .ads ? settings.blockAds : settings.blockTrackers
            guard wanted else { continue }
            if let network = compiled[key(source.id, .network)] { lists.append(network) }
            let hideElements = source.category == .ads ? settings.hideAdPlaceholders : true
            if hideElements, let cosmetic = compiled[key(source.id, .cosmetic)] { lists.append(cosmetic) }
        }
        return lists
    }

    /// Which list (if any) blocks this host. Used for the per-page report.
    func category(forHost host: String, settings: PrivacySettings) -> Blocklist.Category? {
        let suffixes = Blocklist.suffixes(of: host)
        for source in Self.sources where subscription(source.id).isEnabled {
            guard source.category == .ads ? settings.blockAds : settings.blockTrackers,
                  let blocked = blockDomains[source.id] else { continue }
            let excepted = exceptionDomains[source.id] ?? []
            if suffixes.contains(where: { excepted.contains($0) }) { continue }
            if suffixes.contains(where: { blocked.contains($0) }) { return source.category }
        }
        return nil
    }

    // MARK: - Loading & updating

    /// Restores compiled lists from WebKit's cache. Fast; call at launch.
    func loadCached() async {
        for source in Self.sources where subscription(source.id).lastUpdated != nil {
            for part in [Part.network, .cosmetic] {
                if let list = await Self.lookUp(identifier(source.id, part)) {
                    compiled[key(source.id, part)] = list
                }
            }
            let file = Self.domainsURL(source.id)
            let domains = await Task.detached(priority: .utility) { () -> DomainFile? in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return try? JSONDecoder().decode(DomainFile.self, from: data)
            }.value
            if let domains {
                blockDomains[source.id] = Set(domains.block)
                exceptionDomains[source.id] = Set(domains.exceptions)
            }
        }
    }

    /// Updates lists that are missing, stale, or made by an older converter.
    func updateIfNeeded() async {
        for source in Self.sources {
            let sub = subscription(source.id)
            guard sub.isEnabled else { continue }
            let missing = compiled[key(source.id, .network)] == nil
            let outdated = sub.converterVersion != FilterListConverter.version
            let stale = Date().timeIntervalSince(sub.lastChecked ?? .distantPast) > Self.updateInterval
            if missing || outdated || stale {
                await update(source.id, force: missing || outdated)
            }
        }
    }

    func updateAll() async {
        for source in Self.sources where subscription(source.id).isEnabled {
            await update(source.id, force: false)
        }
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        subscriptions[id, default: Subscription()].isEnabled = enabled
        saveState()
        onRulesChanged?()
        if enabled { Task { await updateIfNeeded() } }
    }

    func update(_ id: String, force: Bool) async {
        guard let source = Self.sources.first(where: { $0.id == id }), !updating.contains(id) else { return }
        updating.insert(id)
        defer { updating.remove(id) }

        var sub = subscription(id)
        do {
            let download = try await Self.download(
                from: source.urls,
                etag: force ? nil : sub.etag,
                lastModified: force ? nil : sub.lastModified
            )
            sub.lastChecked = Date()

            if let text = download.text {
                let output = try await Task.detached(priority: .utility) {
                    try FilterListConverter.convert(text)
                }.value

                let network = try await Self.compile(identifier(id, .network), json: output.networkJSON)
                compiled[key(id, .network)] = network
                if output.stats.cosmeticRules > 0 {
                    compiled[key(id, .cosmetic)] = try await Self.compile(identifier(id, .cosmetic), json: output.cosmeticJSON)
                } else {
                    compiled[key(id, .cosmetic)] = nil
                }

                blockDomains[id] = Set(output.blockDomains)
                exceptionDomains[id] = Set(output.exceptionDomains)
                let file = DomainFile(block: output.blockDomains, exceptions: output.exceptionDomains)
                let url = Self.domainsURL(id)
                Task.detached(priority: .utility) {
                    if let data = try? JSONEncoder().encode(file) { try? data.write(to: url, options: .atomic) }
                }

                sub.lastUpdated = Date()
                sub.networkRuleCount = output.stats.networkRules
                sub.cosmeticRuleCount = output.stats.cosmeticRules
                sub.converterVersion = output.version
                sub.etag = download.etag
                sub.lastModified = download.lastModified
                onRulesChanged?()
            }
            sub.lastError = nil
        } catch {
            sub.lastError = error.localizedDescription
        }
        subscriptions[id] = sub
        saveState()
    }

    // MARK: - Helpers

    private func key(_ id: String, _ part: Part) -> String { "\(id)-\(part.rawValue)" }
    private func identifier(_ id: String, _ part: Part) -> String { "neutrin-sub-\(id)-\(part.rawValue)" }

    private struct DomainFile: Codable {
        let block: [String]
        let exceptions: [String]
    }

    private struct Download {
        /// `nil` when the server says the list hasn't changed (HTTP 304).
        var text: String?
        var etag: String?
        var lastModified: String?
    }

    enum FilterListError: LocalizedError {
        case badResponse(Int)
        case notAFilterList

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): "The server answered with error \(code)."
            case .notAFilterList: "The download wasn't a valid filter list."
            }
        }
    }

    private static func download(from urls: [URL], etag: String?, lastModified: String?) async throws -> Download {
        var lastError: Error = URLError(.badURL)
        for url in urls {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
            if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                let newETag = http?.value(forHTTPHeaderField: "ETag")
                let newLastModified = http?.value(forHTTPHeaderField: "Last-Modified")
                if status == 304 { return Download(text: nil, etag: etag, lastModified: lastModified) }
                guard status == 200 else { throw FilterListError.badResponse(status) }
                guard data.count > 10_000, let text = String(data: data, encoding: .utf8),
                      text.hasPrefix("[Adblock") || text.contains("! Title:") else {
                    throw FilterListError.notAFilterList
                }
                return Download(text: text, etag: newETag, lastModified: newLastModified)
            } catch {
                lastError = error // try the mirror
            }
        }
        throw lastError
    }

    private static func lookUp(_ identifier: String) async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        return await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }

    private static func compile(_ identifier: String, json: String) async throws -> WKContentRuleList {
        guard let store = WKContentRuleListStore.default() else { throw URLError(.cannotCreateFile) }
        return try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cannotParseResponse))
                }
            }
        }
    }

    // MARK: - Persistence

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("FilterLists", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var stateURL: URL { directory.appendingPathComponent("subscriptions.json") }

    private static func domainsURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id)-domains.json")
    }

    private static func loadState() -> [String: Subscription] {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode([String: Subscription].self, from: data) else { return [:] }
        return state
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }
}
