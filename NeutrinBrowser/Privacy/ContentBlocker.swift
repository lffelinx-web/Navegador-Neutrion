import WebKit

/// Compiles Neutrin's block lists once and keeps them ready for every web view.
@MainActor
final class ContentBlocker: ObservableObject {
    enum List: String, CaseIterable {
        case ads, trackers, cosmetic

        var identifier: String { "neutrin-\(rawValue)-v\(Blocklist.version)" }

        var json: String {
            switch self {
            case .ads: Blocklist.ruleListJSON(for: .ads)
            case .trackers: Blocklist.ruleListJSON(for: .trackers)
            case .cosmetic: Blocklist.cosmeticRuleListJSON()
            }
        }
    }

    @Published private(set) var compiled: [List: WKContentRuleList] = [:]
    private var isLoading = false

    private var ruleStore: WKContentRuleListStore? { WKContentRuleListStore.default() }

    /// Looks up cached lists and compiles any that are missing or out of date.
    func prepare() async {
        guard !isLoading, compiled.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        await removeOutdatedLists()
        for list in List.allCases {
            var ruleList = await lookUp(list)
            if ruleList == nil {
                ruleList = await compile(list)
            }
            if let ruleList {
                compiled[list] = ruleList
            }
        }
    }

    func ruleLists(for settings: PrivacySettings) -> [WKContentRuleList] {
        var lists: [WKContentRuleList] = []
        if settings.blockAds, let ads = compiled[.ads] { lists.append(ads) }
        if settings.blockTrackers, let trackers = compiled[.trackers] { lists.append(trackers) }
        if settings.blockAds, settings.hideAdPlaceholders, let cosmetic = compiled[.cosmetic] { lists.append(cosmetic) }
        return lists
    }

    private func lookUp(_ list: List) async -> WKContentRuleList? {
        guard let ruleStore else { return nil }
        return await withCheckedContinuation { continuation in
            ruleStore.lookUpContentRuleList(forIdentifier: list.identifier) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }

    private func compile(_ list: List) async -> WKContentRuleList? {
        guard let ruleStore else { return nil }
        return await withCheckedContinuation { continuation in
            ruleStore.compileContentRuleList(forIdentifier: list.identifier, encodedContentRuleList: list.json) { ruleList, error in
                if let error { print("Neutrin: could not compile \(list.identifier): \(error)") }
                continuation.resume(returning: ruleList)
            }
        }
    }

    private func removeOutdatedLists() async {
        guard let ruleStore else { return }
        let current = Set(List.allCases.map(\.identifier))
        let identifiers: [String] = await withCheckedContinuation { continuation in
            ruleStore.getAvailableContentRuleListIdentifiers { continuation.resume(returning: $0 ?? []) }
        }
        for identifier in identifiers where identifier.hasPrefix("neutrin-") && !current.contains(identifier) {
            ruleStore.removeContentRuleList(forIdentifier: identifier) { _ in }
        }
    }
}
