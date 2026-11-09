import Foundation

/// An article extracted by Readability.js.
struct ReaderArticle: Identifiable, Decodable {
    let id = UUID()
    var url: URL?
    let title: String?
    let byline: String?
    let content: String?
    let excerpt: String?
    let siteName: String?
    /// Length of the article text in characters.
    let length: Int?

    private enum CodingKeys: String, CodingKey {
        case title, byline, content, excerpt, siteName, length
    }

    /// Rough estimate: ~5 characters per word, ~220 words per minute.
    var minutesToRead: Int {
        max(1, Int((Double(length ?? 0) / 5 / 220).rounded()))
    }
}

enum ReaderFont: String, Codable, CaseIterable, Identifiable {
    case serif, sans
    var id: String { rawValue }
    var name: String { self == .serif ? "Serif" : "Sans" }
}

enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case auto, light, sepia, dark
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

struct ReaderSettings: Codable, Equatable {
    var fontSize: Double = 19
    var font: ReaderFont = .serif
    var theme: ReaderTheme = .auto

    static let fontSizeRange: ClosedRange<Double> = 14...30

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 19
        font = try c.decodeIfPresent(ReaderFont.self, forKey: .font) ?? .serif
        theme = try c.decodeIfPresent(ReaderTheme.self, forKey: .theme) ?? .auto
    }
}
