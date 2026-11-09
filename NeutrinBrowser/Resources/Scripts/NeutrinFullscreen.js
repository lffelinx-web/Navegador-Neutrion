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

  // Leaving fullscreen (and rotating back) can pause the video. If it was playing
  // a moment ago, keep it playing.
  let lastPlaying = 0;
  document.addEventListener("timeupdate", (event) => {
    if (event.target && !event.target.paused) lastPlaying = Date.now();
  }, true);
  function resumeIfNeeded(video) {
    if (!video || Date.now() - lastPlaying > 1500) return;
    for (const delay of [350, 900]) {
      setTimeout(() => { if (video.paused && !video.ended) video.play().catch(() => {}); }, delay);
    }
  }
  const onElementExit = () => {
    if (!(document.fullscreenElement || document.webkitFullscreenElement)) resumeIfNeeded(document.querySelector("video"));
  };
  document.addEventListener("fullscreenchange", onElementExit);
  document.addEventListener("webkitfullscreenchange", onElementExit);

  // Native player events fire on the <video> itself; listen in the capture phase.
  document.addEventListener("webkitbeginfullscreen", (event) => report(true, event.target), true);
  document.addEventListener("webkitendfullscreen", (event) => {
    report(false, event.target);
    resumeIfNeeded(event.target);
  }, true);
  document.addEventListener("webkitpresentationmodechanged", (event) => {
    const video = event.target;
    if (video && video.webkitPresentationMode) report(video.webkitPresentationMode === "fullscreen", video);
  }, true);
})();
