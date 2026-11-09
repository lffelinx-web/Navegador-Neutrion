const fs = require("fs");
const { JSDOM } = require("jsdom");
const dir = process.argv[2] || require("path").join(__dirname, "../NeutrinBrowser/Resources/Scripts");
const read = (f) => fs.readFileSync(`${dir}/${f}`, "utf8");
let fail = 0;
const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) fail++; };

function makeDom(html, url) {
  const dom = new JSDOM(html, { url, runScripts: "outside-only", pretendToBeVisual: true });
  const msgs = {};
  dom.window.webkit = { messageHandlers: new Proxy({}, { get: (_, n) => ({ postMessage: (m) => (msgs[n] ||= []).push(m) }) }) };
  return { dom, msgs };
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  // --- Shields report (third-party hosts sent to the app)
  const shields = read("NeutrinShields.js");
  let { dom, msgs } = makeDom(`<html><body>
    <script src="https://stats.g.doubleclick.net/x.js"></script>
    <img src="https://www.google-analytics.com/collect?v=1">
    <img src="https://www.google-analytics.com/collect?v=2">
    <img src="https://www.facebook.com/tr?id=1">
    <img src="https://static.example.com/logo.png">
    <a href="https://elsewhere.org/">link</a>
  </body></html>`, "https://news.example.com/article");
  dom.window.eval(shields);
  const s = dom.window.document.createElement("script");
  s.src = "https://ad.doubleclick.net/later.js"; dom.window.document.body.appendChild(s);
  await sleep(1400); // dynamic nodes are checked in batches, once a second
  const got = (msgs.neutrinShields || []).flat().map((x) => x.host + x.path).sort();
  console.log("  reported:", got.join(", "));
  ok(got.includes("stats.g.doubleclick.net/x.js") && got.includes("ad.doubleclick.net/later.js"), "third-party hosts incl. dynamically added");
  ok(got.includes("www.facebook.com/tr") && got.filter((x) => x.startsWith("www.google-analytics")).length === 1, "deduplicated by host + first path segment");
  ok(!got.some((x) => x.includes("example.com") || x.includes("elsewhere.org")), "same-site resources and plain links ignored");

  ({ dom, msgs } = makeDom(`<body><script src="https://static.bbc.co.uk/a.js"></script></body>`, "https://www.bbc.co.uk/"));
  dom.window.eval(shields); await sleep(400);
  ok(!msgs.neutrinShields, "co.uk-style sites treated as first party");

  // --- Filter list converter
  const { neutrinConvertFilterList } = require(`${dir}/NeutrinFilterConverter.js`);
  const sample = [
    "[Adblock Plus 2.0]",
    "! comment",
    "||ads.example.net^",
    "||tracker.io^$third-party",
    "/banner/*/ad_$image,domain=news.com|~sport.news.com",
    "|https://exact.com/path|",
    "@@||ads.example.net/allowed.js",
    "@@||goodsite.org^$document",
    "@@||cleansite.org^$elemhide",
    "||frames.example^$subdocument,script",
    "||nope.example^$popup",
    "||rewrite.example^$redirect=noop.js",
    "/regex-[0-9]+/",
    "example.*##.ad",
    "##.ad-banner",
    "##div[id^=\"google_ads\"]",
    "news.com,blog.com##.sidebar-ad",
    "~safe.com##.promo-box",
    "##.not-everywhere",
    "trusted.com#@#.not-everywhere",
    "##.allowed-all",
    "#@#.allowed-all",
    "shop.com##.price:-abp-has(.x)",
    "site.com#?#.x:has-text(Ad)",
  ].join("\n");
  const out = JSON.parse(neutrinConvertFilterList(sample));
  const net = JSON.parse(out.networkJSON), cos = JSON.parse(out.cosmeticJSON);
  const find = (re) => net.filter((r) => re.test(JSON.stringify(r)));
  const matches = (rule, url) => new RegExp(rule.trigger["url-filter"], rule.trigger["url-filter-is-case-sensitive"] ? "" : "i").test(url);

  const adRule = find(/ads\\\\.example/)[0];
  ok(adRule && matches(adRule, "https://ads.example.net/x.js") && matches(adRule, "https://cdn.ads.example.net/") &&
     !matches(adRule, "https://notads.example.net/") && !matches(adRule, "https://ads.example.network/"), "||domain^ anchors to domain and subdomains");
  const tp = find(/tracker/)[0];
  ok(tp && tp.trigger["load-type"][0] === "third-party", "$third-party -> load-type");
  const banner = find(/banner/)[0];
  ok(banner && banner.trigger["if-domain"][0] === "*news.com" && !banner.trigger["unless-domain"] &&
     banner.trigger["resource-type"][0] === "image" && matches(banner, "https://cdn.x.com/banner/300/ad_1.png"), "domain= and type options");
  const exact = find(/exact/)[0];
  ok(exact && matches(exact, "https://exact.com/path") && !matches(exact, "https://exact.com/path2"), "| anchors");
  const allowed = net.findIndex((r) => r.action.type === "ignore-previous-rules" && /allowed/.test(r.trigger["url-filter"]));
  const blocked = net.findIndex((r) => r === adRule);
  ok(allowed > blocked, "exceptions come after blocks");
  ok(net.some((r) => r.action.type === "ignore-previous-rules" && r.trigger["if-domain"]?.[0] === "*goodsite.org") &&
     cos.some((r) => r.action.type === "ignore-previous-rules" && r.trigger["if-domain"]?.[0] === "*goodsite.org"), "$document exception allows whole site");
  ok(cos.some((r) => r.trigger["if-domain"]?.[0] === "*cleansite.org") &&
     !net.some((r) => r.trigger["if-domain"]?.[0] === "*cleansite.org"), "$elemhide only affects element hiding");
  const frames = find(/frames/);
  ok(frames.length === 2 && frames.some((r) => r.trigger["load-context"]?.[0] === "child-frame"), "subdocument -> child-frame rule");
  ok(!find(/nope|rewrite|regex/).length, "popup / redirect / regex filters skipped");
  const generic = cos.find((r) => r.trigger["url-filter"] === ".*" && !r.trigger["if-domain"] && !r.trigger["unless-domain"] && r.action.type === "css-display-none");
  ok(generic && generic.action.selector.includes(".ad-banner") && !generic.action.selector.includes(".allowed-all") &&
     !generic.action.selector.includes(".not-everywhere"), "generic hiding batched, exceptions respected");
  ok(cos.some((r) => r.trigger["unless-domain"]?.[0] === "*trusted.com" && r.action.selector === ".not-everywhere"), "site exception -> unless-domain");
  ok(cos.some((r) => r.trigger["if-domain"]?.join() === "*blog.com,*news.com" && r.action.selector === ".sidebar-ad"), "site-specific hiding");
  ok(cos.some((r) => r.trigger["unless-domain"]?.[0] === "*safe.com" && r.action.selector === ".promo-box"), "~domain hiding");
  ok(!JSON.stringify(cos).includes("has-text") && !JSON.stringify(cos).includes("-abp-") && !JSON.stringify(cos).includes(".ad\""), "procedural & wildcard-domain filters skipped");
  ok(out.blockDomains.includes("tracker.io") && !out.blockDomains.includes("frames.example"), "plain domains exported for the report");

  // Real lists, if downloaded next to the tests (see README).
  for (const name of ["easylist", "easyprivacy", "easylist-cookie"]) {
    const file = require("path").join(__dirname, `${name}.txt`);
    if (!fs.existsSync(file)) continue;
    const real = JSON.parse(neutrinConvertFilterList(fs.readFileSync(file, "utf8")));
    const rules = JSON.parse(real.networkJSON).concat(JSON.parse(real.cosmeticJSON));
    let invalid = 0;
    for (const r of rules) {
      try { new RegExp(r.trigger["url-filter"]); } catch (_) { invalid++; }
      if (/\{|\(\?|(^|[^\\])\|/.test(r.trigger["url-filter"])) invalid++;
    }
    ok(rules.length > 1000 && rules.length < 150000 && invalid === 0, `${name}: ${rules.length} rules, ${invalid} invalid`);
  }

  // --- Dark mode
  const dark = (on) => read("NeutrinDarkMode.js").replace("__NEUTRIN_DARK_ENABLED__", String(on));
  ({ dom } = makeDom(`<body style="background:#fff"><p>hi</p></body>`, "https://a.com/"));
  dom.window.eval(dark(true));
  ok(!!dom.window.document.getElementById("neutrin-dark-mode"), "light page gets inverted");
  dom.window.eval("__neutrinDarkMode.set(false)");
  ok(!dom.window.document.getElementById("neutrin-dark-mode"), "toggle off removes style");
  ({ dom } = makeDom(`<body style="background:rgb(20,20,24)"><p>hi</p></body>`, "https://b.com/"));
  dom.window.eval(dark(true));
  ok(!dom.window.document.getElementById("neutrin-dark-mode"), "already-dark page left alone");
  ({ dom } = makeDom(`<body><p>hi</p></body>`, "https://c.com/"));
  dom.window.eval(dark(false));
  ok(!dom.window.document.getElementById("neutrin-dark-mode"), "disabled does nothing");

  // --- Reader
  const reader = [read("Readability.js"), read("Readability-readerable.js"), read("NeutrinReader.js")].join("\n;\n");
  const para = "The web has never been more powerful. Yet somehow, it can also feel more distracting, noisier, and harder to make your own. A new generation of browsers is emerging, one that puts focus first. ".repeat(4);
  ({ dom, msgs } = makeDom(`<html><head><title>A Calmer, More Open Web</title></head><body>
    <nav><a href="/">Home</a></nav><article><h1>A Calmer, More Open Web</h1>
    ${Array.from({ length: 8 }, () => `<p>${para}</p>`).join("")}</article>
    <aside class="ad">Buy now</aside></body></html>`, "https://article.space/calm"));
  Object.defineProperty(dom.window.document, "readyState", { value: "complete" });
  dom.window.eval(reader);
  await sleep(50);
  ok(msgs.neutrinReader && msgs.neutrinReader[0].readerable === true, "article detected as readerable");
  const json = dom.window.eval(`(() => { const a = new Readability(document.cloneNode(true)).parse(); return a ? JSON.stringify(a) : ""; })()`);
  const art = JSON.parse(json);
  ok(art.title === "A Calmer, More Open Web" && art.length > 1000 && !art.content.includes("Buy now"), `parse ok (title="${art.title}", length=${art.length})`);
  ({ dom, msgs } = makeDom(`<body><div>Login</div><button>Go</button></body>`, "https://app.example/"));
  Object.defineProperty(dom.window.document, "readyState", { value: "complete" });
  dom.window.eval(reader); await sleep(50);
  ok(msgs.neutrinReader && msgs.neutrinReader[0].readerable === false, "non-article not readerable");

  // --- Fullscreen video reports (for rotating to landscape)
  ({ dom, msgs } = makeDom(`<body><div id="player"><video></video></div></body>`, "https://m.youtube.com/watch"));
  dom.window.eval(read("NeutrinFullscreen.js"));
  const video = dom.window.document.querySelector("video");
  Object.defineProperty(video, "videoWidth", { value: 1920 });
  Object.defineProperty(video, "videoHeight", { value: 1080 });
  video.dispatchEvent(new dom.window.Event("webkitbeginfullscreen"));
  video.dispatchEvent(new dom.window.Event("webkitendfullscreen"));
  const fsMsgs = msgs.neutrinFullscreen || [];
  ok(fsMsgs.length === 2 && fsMsgs[0].active === true && Math.abs(fsMsgs[0].ratio - 16 / 9) < 0.01 && fsMsgs[1].active === false,
     "native video fullscreen reported with aspect ratio");

  // --- GPC
  ({ dom } = makeDom(`<body></body>`, "https://x.com/"));
  dom.window.eval(read("NeutrinGPC.js"));
  ok(dom.window.navigator.globalPrivacyControl === true, "navigator.globalPrivacyControl = true");

  console.log(fail ? `${fail} FAILED` : "ALL PASSED");
  process.exit(fail ? 1 : 0);
})();
