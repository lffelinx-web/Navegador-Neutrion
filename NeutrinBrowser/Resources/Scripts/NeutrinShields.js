// Neutrin Shields – page report.
// Runs in an isolated content world. Collects the third-party hosts the page
// tries to load (scripts, images, frames…) and sends them to the app, which
// checks them against the block lists to show what Shields stopped.
(() => {
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.neutrinShields;
  if (!handler) return;

  // Rough "same site" check (example.com vs cdn.example.com, also co.uk-style).
  function site(host) {
    const parts = host.split(".");
    if (parts.length <= 2) return host;
    const tld = parts[parts.length - 1], sld = parts[parts.length - 2];
    const keep = tld.length === 2 && sld.length <= 3 ? 3 : 2;
    return parts.slice(-keep).join(".");
  }
  const pageSite = site(location.hostname);
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
    if (site(host) === pageSite) return;
    const segment = "/" + (url.pathname.split("/")[1] || "");
    const key = host + segment;
    if (seen.has(key)) return;
    seen.add(key);
    pending.push({ host, path: segment });
    if (!timer) timer = setTimeout(flush, 250);
  }

  const SELECTOR = "script[src],img[src],iframe[src],link[href],source[src],embed[src],object[data],video[src],audio[src]";
  function inspect(el) {
    if (el.tagName === "LINK" && !/stylesheet|preload|prefetch|icon/i.test(el.rel || "")) return;
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
