// Neutrin – samples the background color at the top and bottom of the visible page
// so the status bar area and the toolbar can blend in with the site.
(() => {
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.neutrinColors;
  if (!handler) return;

  const isVisible = (color) => color && color !== "transparent" && !/rgba\([^)]*,\s*0(\.0+)?\)$/.test(color);
  function colorAt(y) {
    let el = document.elementFromPoint(window.innerWidth / 2, y);
    while (el) {
      const color = getComputedStyle(el).backgroundColor;
      if (isVisible(color)) return color;
      el = el.parentElement;
    }
    const root = getComputedStyle(document.body || document.documentElement).backgroundColor;
    return isVisible(root) ? root : "rgb(255, 255, 255)";
  }

  let last = "";
  let scheduled = false;
  function sample() {
    scheduled = false;
    const top = colorAt(1);
    const bottom = colorAt(window.innerHeight - 2);
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
