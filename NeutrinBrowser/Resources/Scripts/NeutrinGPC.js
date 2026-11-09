// Global Privacy Control: tells sites the user does not want their data sold or shared.
(() => {
  try {
    Object.defineProperty(Navigator.prototype, "globalPrivacyControl", {
      get: () => true, configurable: true, enumerable: true,
    });
  } catch (_) {}
})();
