import Foundation

/// Removes tracking parameters (utm_*, fbclid, gclid…) from links.
enum LinkCleaner {
    private static let parameters: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "igshid", "igsh", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "oly_anon_id",
        "oly_enc_id", "vero_id", "vero_conv", "li_fat_id", "wickedid", "rb_clickid", "s_cid",
        "_openstat", "__s", "ref_src", "ref_url", "si",
    ]

    /// Returns the cleaned URL, or `nil` when nothing needed removing.
    static func clean(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else { return nil }
        let kept = items.filter { !isTrackingParameter($0.name, host: url.host) }
        guard kept.count != items.count else { return nil }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url
    }

    /// The cleaned URL if there was something to clean, otherwise the original.
    static func cleaned(_ url: URL) -> URL { clean(url) ?? url }

    private static func isTrackingParameter(_ name: String, host: String?) -> Bool {
        let lower = name.lowercased()
        // "si" is a tracking id on YouTube/Spotify share links, but a normal parameter elsewhere.
        if lower == "si" {
            guard let host else { return false }
            return ["youtube.com", "youtu.be", "spotify.com"].contains { host == $0 || host.hasSuffix("." + $0) }
        }
        return lower.hasPrefix("utm_") || parameters.contains(lower)
    }
}
