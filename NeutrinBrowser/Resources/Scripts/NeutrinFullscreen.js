// Neutrin – tells the app when a video goes fullscreen, so it can rotate to landscape.
// Covers both the Fullscreen API (requestFullscreen) and iOS's native video player
// (webkitEnterFullscreen), which is what YouTube and most sites use on iPhone.
(() => {
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.neutrinFullscreen;
  if (!handler) return;

  const ratioOf = (video) => (video && video.videoHeight ? video.videoWidth / video.videoHeight : 0);
  const videoIn = (el) => (!el ? null : el.tagName === "VIDEO" ? el : el.querySelector("video"));
  const report = (active, video) => handler.postMessage({ active, ratio: ratioOf(video) });

  const onElementFullscreen = () => {
    const el = document.fullscreenElement || document.webkitFullscreenElement;
    report(!!el, videoIn(el) || document.querySelector("video"));
  };
  document.addEventListener("fullscreenchange", onElementFullscreen);
  document.addEventListener("webkitfullscreenchange", onElementFullscreen);

  // Native player events fire on the <video> itself; listen in the capture phase.
  document.addEventListener("webkitbeginfullscreen", (event) => report(true, event.target), true);
  document.addEventListener("webkitendfullscreen", (event) => report(false, event.target), true);
  document.addEventListener("webkitpresentationmodechanged", (event) => {
    const video = event.target;
    if (video && video.webkitPresentationMode) report(video.webkitPresentationMode === "fullscreen", video);
  }, true);
})();
