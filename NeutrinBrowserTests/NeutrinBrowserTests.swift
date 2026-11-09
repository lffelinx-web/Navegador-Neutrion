import XCTest
import WebKit
@testable import NeutrinBrowser

final class URLResolverTests: XCTestCase {
    func testFullAddressIsKept() {
        XCTAssertEqual(URLResolver.resolve("https://example.com/a?b=1", engine: .duckDuckGo)?.absoluteString,
                       "https://example.com/a?b=1")
    }

    func testBareDomainUsesHTTPS() {
        XCTAssertEqual(URLResolver.resolve("  example.com/path ", engine: .duckDuckGo)?.absoluteString,
                       "https://example.com/path")
    }

    func testLocalhostUsesHTTP() {
        XCTAssertEqual(URLResolver.resolve("localhost:3000", engine: .duckDuckGo)?.scheme, "http")
    }

    func testWordsBecomeASearch() throws {
        let url = try XCTUnwrap(URLResolver.resolve("calm web", engine: .duckDuckGo))
        XCTAssertEqual(url.host, "duckduckgo.com")
        XCTAssertTrue(url.absoluteString.contains("q=calm%20web"))
    }

    func testStartpageUsesQueryParameter() throws {
        let url = try XCTUnwrap(URLResolver.resolve("privacy", engine: .startpage))
        XCTAssertTrue(url.absoluteString.contains("query=privacy"))
    }

    func testEmptyInput() {
        XCTAssertNil(URLResolver.resolve("   ", engine: .google))
    }
}

final class LinkCleanerTests: XCTestCase {
    func testRemovesTrackingParameters() throws {
        let url = URL(string: "https://shop.com/item?id=7&utm_source=mail&utm_campaign=x&fbclid=abc&gclid=1")!
        XCTAssertEqual(try XCTUnwrap(LinkCleaner.clean(url)).absoluteString, "https://shop.com/item?id=7")
    }

    func testDropsEmptyQuery() throws {
        let url = URL(string: "https://news.com/a?utm_medium=social")!
        XCTAssertEqual(try XCTUnwrap(LinkCleaner.clean(url)).absoluteString, "https://news.com/a")
    }

    func testLeavesCleanLinksAlone() {
        XCTAssertNil(LinkCleaner.clean(URL(string: "https://search.com/?q=utm")!))
        XCTAssertNil(LinkCleaner.clean(URL(string: "https://example.com/")!))
    }

    func testSiOnlyRemovedOnYouTubeAndSpotify() {
        XCTAssertNotNil(LinkCleaner.clean(URL(string: "https://youtu.be/abc?si=xyz")!))
        XCTAssertNil(LinkCleaner.clean(URL(string: "https://example.com/?si=units")!))
    }
}

final class BlocklistTests: XCTestCase {
    private let all: Set<Blocklist.Category> = [.ads, .trackers]

    func testSuffixes() {
        XCTAssertEqual(Blocklist.suffixes(of: "a.b.Example.com"), ["a.b.example.com", "b.example.com", "example.com"])
    }

    func testThirdPartyAdIsClassified() {
        XCTAssertEqual(Blocklist.category(forHost: "stats.g.doubleclick.net", path: "/x", pageHost: "news.com", categories: all), .ads)
        XCTAssertEqual(Blocklist.category(forHost: "www.google-analytics.com", path: "/collect", pageHost: "news.com", categories: all), .trackers)
    }

    func testRespectsEnabledCategories() {
        XCTAssertNil(Blocklist.category(forHost: "doubleclick.net", path: "/", pageHost: "news.com", categories: [.trackers]))
    }

    func testFirstPartyIsNotBlocked() {
        XCTAssertNil(Blocklist.category(forHost: "ads.doubleclick.net", path: "/", pageHost: "www.doubleclick.net", categories: all))
    }

    func testFacebookPixelOnlyByPathAndNotOnFacebook() {
        XCTAssertEqual(Blocklist.category(forHost: "www.facebook.com", path: "/tr", pageHost: "shop.com", categories: all), .trackers)
        XCTAssertNil(Blocklist.category(forHost: "www.facebook.com", path: "/photos", pageHost: "shop.com", categories: all))
        XCTAssertNil(Blocklist.category(forHost: "connect.facebook.net", path: "/sdk.js", pageHost: "www.instagram.com", categories: all))
    }

    func testURLFilterShape() {
        let filter = Blocklist.urlFilter(for: .init(domain: "doubleclick.net", category: .ads))
        let regex = try! NSRegularExpression(pattern: filter, options: .caseInsensitive)
        func hit(_ s: String) -> Bool { regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
        XCTAssertTrue(hit("https://ad.doubleclick.net/x"))
        XCTAssertTrue(hit("https://doubleclick.net/"))
        XCTAssertFalse(hit("https://notdoubleclick.net/"))
        XCTAssertFalse(hit("https://doubleclick.net.evil.com/"))
    }
}

final class CodableCompatibilityTests: XCTestCase {
    func testPrivacySettingsDefaultsForMissingKeys() throws {
        let settings = try JSONDecoder().decode(PrivacySettings.self, from: Data(#"{"blockAds":false}"#.utf8))
        XCTAssertFalse(settings.blockAds)
        XCTAssertTrue(settings.blockTrackers)
        XCTAssertEqual(settings.websiteDarkMode, .matchSystem)
    }

    func testOldTabRecordsLoadAsNormalTabs() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","spaceID":"6F9619FF-8B86-D011-B42D-00CF4FC964FE","title":"A"}"#
        let tab = try JSONDecoder().decode(TabRecord.self, from: Data(json.utf8))
        XCTAssertFalse(tab.isPrivate)
        XCTAssertNil(tab.url)
        XCTAssertEqual(tab.displayTitle, "A")
    }

    func testReaderSettingsDefaults() throws {
        let settings = try JSONDecoder().decode(ReaderSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings, ReaderSettings())
    }
}

final class ReaderTemplateTests: XCTestCase {
    func testEscapesTextAndLocksDownPage() throws {
        let json = #"{"title":"<script>alert(1)</script> & more","byline":null,"content":"<p>Body text</p>","excerpt":null,"siteName":"Tech","length":2200}"#
        var article = try JSONDecoder().decode(ReaderArticle.self, from: Data(json.utf8))
        article.url = URL(string: "https://article.space/calm")
        let html = ReaderTemplate.html(for: article, settings: ReaderSettings())
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; more"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("2 min de lectura"))
        XCTAssertTrue(html.contains("article.space"))
    }
}

final class FilterListConverterTests: XCTestCase {
    static let sample = """
    [Adblock Plus 2.0]
    ! Title: Sample
    ||ads.example.net^
    ||tracker.io^$third-party
    /banner/*/ad_$image,domain=news.com|~sport.news.com
    @@||ads.example.net/allowed.js
    @@||goodsite.org^$document
    ||frames.example^$subdocument,script
    ||nope.example^$popup
    ##.ad-banner
    news.com,blog.com##.sidebar-ad
    shop.com##.price:-abp-has(.x)
    """

    func testConvertsInJavaScriptCore() throws {
        let output = try FilterListConverter.convert(Self.sample)
        XCTAssertEqual(output.version, FilterListConverter.version, "Swift and JS converter versions must match")
        XCTAssertGreaterThan(output.stats.networkRules, 4)
        XCTAssertGreaterThan(output.stats.cosmeticRules, 1)
        XCTAssertTrue(output.blockDomains.contains("tracker.io"))
        XCTAssertFalse(output.networkJSON.contains("nope.example"))
    }
}

/// Compiles rules with the real WebKit compiler, so a format WebKit rejects fails here, not on users' phones.
@MainActor
final class ContentRuleCompilationTests: XCTestCase {
    private var store: WKContentRuleListStore!
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = WKContentRuleListStore(url: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func compile(_ json: String, _ identifier: String) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "Neutrin", code: 1))
                }
            }
        }
    }

    func testBuiltInListsCompile() async throws {
        _ = try await compile(Blocklist.ruleListJSON(for: .ads), "ads")
        _ = try await compile(Blocklist.ruleListJSON(for: .trackers), "trackers")
        _ = try await compile(Blocklist.cosmeticRuleListJSON(), "cosmetic")
    }

    func testConvertedSampleCompiles() async throws {
        let output = try FilterListConverter.convert(FilterListConverterTests.sample)
        _ = try await compile(output.networkJSON, "sample-network")
        _ = try await compile(output.cosmeticJSON, "sample-cosmetic")
    }

    /// Downloads the real lists; skipped when there's no network.
    func testRealEasyListsCompile() async throws {
        for (name, address) in [("easylist", "https://easylist.to/easylist/easylist.txt"),
                                ("easyprivacy", "https://easylist.to/easylist/easyprivacy.txt")] {
            var request = URLRequest(url: URL(string: address)!)
            request.timeoutInterval = 30
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else {
                throw XCTSkip("Couldn't download \(name)")
            }
            let started = Date()
            let output = try await Task.detached { try FilterListConverter.convert(text) }.value
            let converted = Date()
            _ = try await compile(output.networkJSON, "\(name)-network")
            if output.stats.cosmeticRules > 0 {
                _ = try await compile(output.cosmeticJSON, "\(name)-cosmetic")
            }
            print("Neutrin: \(name) – \(output.stats.networkRules) network + \(output.stats.cosmeticRules) cosmetic rules; "
                  + "convert \(String(format: "%.1f", converted.timeIntervalSince(started)))s, "
                  + "compile \(String(format: "%.1f", Date().timeIntervalSince(converted)))s")
        }
    }
}
