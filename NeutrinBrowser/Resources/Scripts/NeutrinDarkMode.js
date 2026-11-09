// Neutrin dark mode for websites.
// Inverts light pages (and re-inverts media so photos look right). Pages that
// are already dark are left alone.
(() => {
  const STYLE_ID = "neutrin-dark-mode";
  const CSS =
    "html{filter:invert(1) hue-rotate(180deg)!important}" +
    "img,video,picture,canvas,iframe,embed,object,svg image,[style*='background-image']" +
    "{filter:invert(1) hue-rotate(180deg)!important}";
  let wanted = __NEUTRIN_DARK_ENABLED__;

  function addStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = CSS;
    (document.head || document.documentElement).appendChild(style);
  }
  function removeStyle() {
    const style = document.getElementById(STYLE_ID);
    if (style) style.remove();
  }
  function backgroundOf(el) {
    if (!el) return null;
    const match = getComputedStyle(el).backgroundColor.match(/rgba?\(([^)]+)\)/);
    if (!match) return null;
    const parts = match[1].split(",").map(parseFloat);
    if (parts.length === 4 && parts[3] < 0.1) return null; // transparent
    return parts;
  }
  function pageIsAlreadyDark() {
    const rgb = backgroundOf(document.body) || backgroundOf(document.documentElement);
    if (!rgb) return false; // nothing set: browsers default to white
    const [r, g, b] = rgb.map((v) => v / 255);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.35;
  }
  function apply() {
    // Style is removed and re-added in the same task, so nothing flashes.
    removeStyle();
    if (!wanted) return;
    // Neutrin's reader view has its own themes.
    if (document.documentElement.dataset.neutrinReader) return;
    if (document.body && pageIsAlreadyDark()) return;
    addStyle();
  }

  window.__neutrinDarkMode = { set(on) { wanted = !!on; apply(); } };
  apply();
  document.addEventListener("DOMContentLoaded", apply);
  window.addEventListener("load", apply);
})();
