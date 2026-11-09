import Foundation

/// Neutrin's built-in list of ad and tracker hosts.
///
/// Each entry becomes a WKContentRuleList "block" rule for third-party requests,
/// and the same data feeds the page report script so the app can show what was blocked.
enum Blocklist {
    /// Bump when the lists change so compiled rule lists are rebuilt.
    static let version = 1

    enum Category: String, CaseIterable {
        case ads, trackers
    }

    struct Entry {
        let domain: String
        var path: String?
        let category: Category
        /// Pages on these sites keep the resource (it's their own service).
        var unlessDomains: [String] = []
    }

    // MARK: - Ads

    static let adDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "googletagservices.com", "2mdn.net", "adnxs.com", "adsrvr.org", "criteo.com", "criteo.net",
        "taboola.com", "outbrain.com", "amazon-adsystem.com", "pubmatic.com", "rubiconproject.com",
        "openx.net", "casalemedia.com", "indexww.com", "moatads.com", "adform.net", "smartadserver.com",
        "yieldmo.com", "sharethrough.com", "teads.tv", "media.net", "zedo.com", "revcontent.com",
        "mgid.com", "popads.net", "propellerads.com", "adcolony.com", "bidswitch.net", "3lift.com",
        "contextweb.com", "lijit.com", "sovrn.com", "adroll.com", "serving-sys.com", "flashtalking.com",
        "adsafeprotected.com", "doubleverify.com", "33across.com", "gumgum.com", "spotxchange.com",
        "spotx.tv", "springserve.com", "undertone.com", "yieldlab.net", "adition.com", "adtech.de",
        "advertising.com", "ads.yahoo.com", "gemini.yahoo.com", "adsymptotic.com", "adhigh.net",
        "admixer.net", "adkernel.com", "adblade.com", "adbutler.com", "adzerk.net", "buysellads.com",
        "carbonads.net", "exoclick.com", "juicyads.com", "trafficjunky.net", "hilltopads.net",
        "onclickads.net", "popcash.net", "adsterra.com", "infolinks.com", "kargo.com", "nativo.com",
        "triplelift.com", "districtm.io", "emxdgt.com", "smaato.net", "inmobi.com", "applovin.com",
        "unityads.unity3d.com", "ads.linkedin.com", "ads.pinterest.com", "ads.tiktok.com",
        "ads-api.twitter.com", "static.ads-twitter.com", "ads.reddit.com", "a-ads.com",
    ]

    // MARK: - Trackers

    static let trackerDomains = [
        "google-analytics.com", "googletagmanager.com", "analytics.google.com", "ssl.google-analytics.com",
        "scorecardresearch.com", "quantserve.com", "quantcount.com", "hotjar.com", "hotjar.io",
        "mixpanel.com", "mxpnl.com", "segment.io", "cdn.segment.com", "api.segment.io", "amplitude.com",
        "fullstory.com", "mouseflow.com", "crazyegg.com", "luckyorange.com", "luckyorange.net",
        "chartbeat.com", "chartbeat.net", "nr-data.net", "clarity.ms", "bat.bing.com",
        "analytics.twitter.com", "analytics.tiktok.com", "snap.licdn.com", "px.ads.linkedin.com",
        "ct.pinterest.com", "sc-static.net", "tr.snapchat.com", "appsflyer.com", "adjust.com",
        "kochava.com", "branch.io", "omtrdc.net", "demdex.net", "everesttech.net", "krxd.net",
        "bluekai.com", "exelator.com", "rlcdn.com", "tapad.com", "agkn.com", "crwdcntrl.net",
        "mathtag.com", "addthis.com", "sharethis.com", "mc.yandex.ru", "heapanalytics.com",
        "statcounter.com", "histats.com", "parsely.com", "parse.ly", "comscore.com", "newrelic.com",
        "bugsnag.com", "sentry-cdn.com", "pingdom.net", "inspectlet.com", "clicktale.net",
        "contentsquare.net", "kissmetrics.com", "woopra.com", "matomo.cloud", "piwik.pro",
        "optimizely.com", "abtasty.com", "qualtrics.com", "onesignal.com", "pushwoosh.com",
        "liadm.com", "id5-sync.com", "zemanta.com", "bounceexchange.com",
        "cquotient.com", "dotomi.com", "pippio.com", "rfihub.com", "turn.com", "eyeota.net",
        "lotame.com", "permutive.com", "permutive.app", "ml314.com", "taboola-tracking.com",
        "smartlook.com", "logrocket.io", "lr-ingest.io", "posthog.com", "plausible.io", "stats.wp.com",
    ]

    static var entries: [Entry] {
        var list = adDomains.map { Entry(domain: $0, category: .ads) }
        list += trackerDomains.map { Entry(domain: $0, category: .trackers) }
        // Facebook's tracking scripts and pixel. Facebook's own sites still work.
        let meta = ["facebook.com", "facebook.net", "instagram.com", "messenger.com", "whatsapp.com", "threads.net"]
        list.append(Entry(domain: "connect.facebook.net", category: .trackers, unlessDomains: meta))
        list.append(Entry(domain: "facebook.com", path: "/tr", category: .trackers, unlessDomains: meta))
        list.append(Entry(domain: "pixel.facebook.com", category: .trackers, unlessDomains: meta))
        return list
    }

    /// Element-hiding rules for the empty boxes ads leave behind.
    static let cosmeticSelectors = [
        "ins.adsbygoogle", ".adsbygoogle", "[id^='div-gpt-ad']", "[id^='google_ads_iframe']",
        "[id^='taboola-']", ".trc_related_container", ".OUTBRAIN", "[data-widget-id^='outbrain']",
        "amp-ad", "amp-embed[type='taboola']", "amp-embed[type='outbrain']", "[data-ad-slot]",
        "iframe[src*='doubleclick.net']", "iframe[src*='googlesyndication.com']",
    ]

    // MARK: - Builders

    /// WebKit content-blocker JSON for one category.
    static func ruleListJSON(for category: Category) -> String {
        let rules: [[String: Any]] = entries.filter { $0.category == category }.map { entry in
            var trigger: [String: Any] = [
                "url-filter": urlFilter(for: entry),
                "load-type": ["third-party"],
            ]
            if !entry.unlessDomains.isEmpty {
                trigger["unless-domain"] = entry.unlessDomains.map { "*" + $0 }
            }
            return ["trigger": trigger, "action": ["type": "block"]]
        }
        return encode(rules)
    }

    static func cosmeticRuleListJSON() -> String {
        encode([[
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": cosmeticSelectors.joined(separator: ", ")],
        ]])
    }

    /// Data for NeutrinShields.js, limited to the categories being blocked.
    static func pageReportRulesJSON(categories: Set<Category>) -> String {
        let rules: [[String: Any]] = entries.filter { categories.contains($0.category) }.map { entry in
            var rule: [String: Any] = ["d": entry.domain, "c": entry.category.rawValue]
            if let path = entry.path { rule["p"] = path }
            if !entry.unlessDomains.isEmpty { rule["u"] = entry.unlessDomains }
            return rule
        }
        return encode(rules)
    }

    /// Matches the domain and any subdomain, e.g. `^https?://([^/]+\.)?doubleclick\.net[/:]`.
    static func urlFilter(for entry: Entry) -> String {
        let domain = entry.domain.replacingOccurrences(of: ".", with: "\\.")
        let prefix = "^https?://([^/]+\\.)?" + domain
        if let path = entry.path {
            return prefix + path + "[/?]"
        }
        return prefix + "[/:]"
    }

    private static func encode(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}
