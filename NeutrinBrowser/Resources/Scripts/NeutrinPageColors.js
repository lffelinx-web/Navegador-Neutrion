// Neutrin – samples the background color at the top and bottom of the visible page
// so the status bar area and the toolbar can blend in with the site.
(() => {
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.neutrinColors;
  if (!handler) return;

  const isVisible = (color) => color && color !== "transparent" && !/rgba\([^)]*,\s*0(\.0+)?\)$/.test(color);
  // Only bars that stay put (fixed/sticky headers and footers) or the page's own
  // background count. Content scrolling past the edge (photos, cards) is ignored,
  // so the bars don't flash dark when an image passes by.
  function rootColor() {
    for (const node of [document.body, document.documentElement]) {
      const color = node && getComputedStyle(node).backgroundColor;
      if (isVisible(color)) return color;
    }
    return null; // nothing painted: the app falls back to the page's theme-color
  }
  function colorAt(y) {
    let el = document.elementFromPoint(window.innerWidth / 2, y);
    let pinned = null;
    for (let node = el; node && node !== document.body && node !== document.documentElement; node = node.parentElement) {
      const position = getComputedStyle(node).position;
      if (position === "fixed" || position === "sticky") { pinned = node; break; }
    }
    if (pinned) {
      // The pinned bar's own color, or the first colored element inside it at that point.
      for (let node = el; node; node = node.parentElement) {
        const color = getComputedStyle(node).backgroundColor;
        if (isVisible(color)) return color;
        if (node === pinned) break;
      }
    }
    return rootColor();
  }

  let last = "";
  let scheduled = false;
  function sample() {
    scheduled = false;
    const top = colorAt(1);
    const bottom = colorAt(window.innerHeight - 2);
    // Keep wide-gamut / HDR images at normal brightness (iOS 26 can show them very bright).
    if (!document.getElementById("neutrin-sdr")) {
      const style = document.createElement("style");
      style.id = "neutrin-sdr";
      style.textContent = ":root{dynamic-range-limit:standard}img,video,picture{dynamic-range-limit:standard}";
      (document.head || document.documentElement).appendChild(style);
    }
    const inverted = !!document.getElementById("neutrin-dark-mode");
    const key = top + bottom + inverted;
    if (key === last) return;
    last = key;
    handler.postMessage({ top, bottom, inverted });
  }
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(() => requestAnimationFrame(sample), 150);
  }

  sample();
  window.addEventListener("load", schedule);
  window.addEventListener("scroll", schedule, { passive: true });
  window.addEventListener("resize", schedule);
})();
