// Neutrin reader mode: tells the app whether the page looks like an article.
// Readability.js and Readability-readerable.js are prepended to this file.
(() => {
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.neutrinReader;
  if (!handler) return;
  let last = null;
  function check() {
    let readerable = false;
    try { readerable = isProbablyReaderable(document); } catch (_) {}
    if (readerable !== last) {
      last = readerable;
      handler.postMessage({ readerable });
    }
  }
  if (document.readyState === "complete") check();
  else window.addEventListener("load", check);
  setTimeout(check, 1500);
})();
