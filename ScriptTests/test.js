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
  // --- Shields report
  const rules = [
    { d: "doubleclick.net", c: "ads" },
    { d: "google-analytics.com", c: "trackers" },
    { d: "facebook.com", p: "/tr", c: "trackers", u: ["facebook.com"] },
    { d: "connect.facebook.net", c: "trackers", u: ["facebook.com"] },
  ];
  const shields = read("NeutrinShields.js").replace("__NEUTRIN_RULES__", JSON.stringify(rules));
  let { dom, msgs } = makeDom(`<html><body>
    <script src="https://stats.g.doubleclick.net/x.js"></script>
    <img src="https://www.google-analytics.com/collect?v=1">
    <img src="https://www.facebook.com/tr?id=1">
    <img src="https://www.facebook.com/photo.jpg">
    <script src="https://cdn.example.org/app.js"></script>
    <script src="https://connect.facebook.net/sdk.js"></script>
  </body></html>`, "https://news.example.com/article");
  dom.window.eval(shields);
  const s = dom.window.document.createElement("script");
  s.src = "https://ad.doubleclick.net/later.js"; dom.window.document.body.appendChild(s);
  await sleep(400);
  const got = (msgs.neutrinShields || []).flat().map((x) => `${x.category}:${x.host}`).sort();
  console.log("  reported:", got.join(", "));
  ok(got.includes("ads:stats.g.doubleclick.net") && got.includes("ads:ad.doubleclick.net"), "ads incl. dynamically added");
  ok(got.includes("trackers:www.google-analytics.com"), "tracker reported");
  ok(got.includes("trackers:www.facebook.com") && got.length === 5, "fb pixel path only, cdn ignored");

  ({ dom, msgs } = makeDom(`<body><script src="https://connect.facebook.net/sdk.js"></script></body>`, "https://www.facebook.com/"));
  dom.window.eval(shields); await sleep(400);
  ok(!msgs.neutrinShields, "first-party / unless-domain not reported");

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

  // --- GPC
  ({ dom } = makeDom(`<body></body>`, "https://x.com/"));
  dom.window.eval(read("NeutrinGPC.js"));
  ok(dom.window.navigator.globalPrivacyControl === true, "navigator.globalPrivacyControl = true");

  console.log(fail ? `${fail} FAILED` : "ALL PASSED");
  process.exit(fail ? 1 : 0);
})();
