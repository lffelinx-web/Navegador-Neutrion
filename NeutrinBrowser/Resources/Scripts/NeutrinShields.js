// Neutrin Shields – page report.
// Runs in an isolated content world. Looks for elements that point at blocked
// ad/tracker hosts (their requests were already stopped by WKContentRuleList)
// and reports them to the app so the user can see what was blocked.
(() => {
  const RULES = __NEUTRIN_RULES__; // [{ d: domain, p: pathPrefix|null, c: "ads"|"trackers", u: [unlessDomain] }]
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.neutrinShields;
  if (!handler || !RULES.length) return;

  const pageHost = location.hostname;
  const matches = (host, domain) => host === domain || host.endsWith("." + domain);
  const seen = new Set();
  let pending = [];
  let timer = null;

  function flush() {
    timer = null;
    if (pending.length) handler.postMessage(pending.splice(0));
  }

  function check(raw) {
    if (!raw) return;
    let url;
    try { url = new URL(raw, location.href); } catch (_) { return; }
    if (url.protocol !== "http:" && url.protocol !== "https:") return;
    const host = url.hostname;
    for (const rule of RULES) {
      if (!matches(host, rule.d)) continue;
      if (rule.p && !url.pathname.startsWith(rule.p)) continue;
      if (matches(pageHost, rule.d)) return; // first party: not blocked
      if (rule.u && rule.u.some((d) => matches(pageHost, d))) return;
      const key = rule.c + "|" + host;
      if (!seen.has(key)) {
        seen.add(key);
        pending.push({ host, category: rule.c });
        if (!timer) timer = setTimeout(flush, 250);
      }
      return;
    }
  }

  const SELECTOR = "script[src],img[src],iframe[src],link[href],source[src],embed[src],object[data],video[src],audio[src]";
  function inspect(el) {
    check(el.getAttribute("src") || el.getAttribute("href") || el.getAttribute("data"));
  }
  function scan(root) {
    if (root.matches && root.matches(SELECTOR)) inspect(root);
    if (root.querySelectorAll) root.querySelectorAll(SELECTOR).forEach(inspect);
  }

  scan(document);
  new MutationObserver((mutations) => {
    for (const m of mutations) {
      if (m.type === "attributes") inspect(m.target);
      else m.addedNodes.forEach((n) => n.nodeType === 1 && scan(n));
    }
  }).observe(document.documentElement, {
    childList: true, subtree: true, attributes: true, attributeFilter: ["src", "href", "data"],
  });
})();
