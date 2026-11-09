// Neutrin filter-list converter.
//
// Turns an Adblock Plus–style list (EasyList, EasyPrivacy) into WebKit
// content-blocker rules. Runs on the device in JavaScriptCore (no DOM), and in
// Node for tests. Anything WebKit can't express is skipped, never guessed.
//
//   neutrinConvertFilterList(text) -> JSON string:
//   { networkJSON, cosmeticJSON, blockDomains, exceptionDomains, stats }

var NEUTRIN_CONVERTER_VERSION = 1;

var neutrinConvertFilterList = (function () {
  var MAX_RULES = 145000; // WebKit's limit is 150,000 per list.
  var SELECTORS_PER_RULE = 400;
  var SEPARATOR = "[^a-zA-Z0-9_.%-]";
  var DOMAIN_ANCHOR = "^[a-z][a-z0-9+.-]*://([^/]+\\.)?";

  // ABP resource types -> WebKit resource-type (+ load-context for frames).
  var TYPE_MAP = {
    script: "script",
    image: "image",
    stylesheet: "style-sheet",
    font: "font",
    media: "media",
    object: "media",
    xmlhttprequest: "raw",
    xhr: "raw",
    websocket: "raw",
    other: "raw",
    ping: "ping",
    subdocument: "subdocument",
    frame: "subdocument",
  };
  var ALL_TYPES = ["script", "image", "stylesheet", "font", "media", "object", "xmlhttprequest", "websocket", "other", "ping", "subdocument"];

  // Options that don't change what we block.
  var IGNORED_OPTIONS = { important: 1, "~important": 1 };
  // Options we can't express: the whole filter is skipped.
  var UNSUPPORTED_OPTIONS = {
    popup: 1, popunder: 1, csp: 1, redirect: 1, "redirect-rule": 1, rewrite: 1, removeparam: 1,
    replace: 1, header: 1, permissions: 1, cookie: 1, empty: 1, mp4: 1, "inline-script": 1,
    "inline-font": 1, badfilter: 1, all: 1, to: 1, denyallow: 1, method: 1, strict1p: 1,
    strict3p: 1, urltransform: 1, specifichide: 1, shide: 1, genericblock: 1, sitekey: 1,
    webrtc: 1, jsinject: 1, content: 1, urlblock: 1, network: 1, stealth: 1, cname: 1,
  };
  var PROCEDURAL = /:-abp-|:has-text\(|:contains\(|:xpath\(|:matches-css|:upward\(|:remove\(|:style\(|:matches-path\(|:min-text-length\(|:watch-attr\(|:others\(|:if\(|:if-not\(|:nth-ancestor\(|:matches-attr\(|:matches-property\(|:-ext-|:matches-media\(/;
  var COSMETIC = /^([^\/|@#^$\s]*)(#@?[?$%]?#)(.+)$/;
  var PLAIN_DOMAIN = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;

  function isASCII(s) {
    for (var i = 0; i < s.length; i++) if (s.charCodeAt(i) > 126) return false;
    return true;
  }

  // "a.com,~b.a.com" or "a.com|~b.com" -> { include: [...], exclude: [...], dropped: n }
  function parseDomains(list, sep) {
    var result = { include: [], exclude: [], dropped: 0 };
    if (!list) return result;
    var parts = list.split(sep);
    for (var i = 0; i < parts.length; i++) {
      var d = parts[i].trim().toLowerCase();
      if (!d) continue;
      var negated = d.charAt(0) === "~";
      if (negated) d = d.slice(1);
      // WebKit can't match "example.*" or regex domains.
      if (!PLAIN_DOMAIN.test(d)) { result.dropped++; continue; }
      (negated ? result.exclude : result.include).push(d);
    }
    return result;
  }

  function star(domains) {
    return domains.map(function (d) { return "*" + d; });
  }

  // ABP pattern -> WebKit url-filter regex, or null if it can't be expressed.
  function toURLFilter(pattern) {
    if (!isASCII(pattern)) return null;
    var re = "";
    var i = 0;
    var anchoredStart = false;
    if (pattern.indexOf("||") === 0) {
      re = DOMAIN_ANCHOR;
      i = 2;
      anchoredStart = true;
    } else if (pattern.charAt(0) === "|") {
      re = "^";
      i = 1;
      anchoredStart = true;
    }
    var end = pattern.length;
    var anchoredEnd = false;
    if (end > i && pattern.charAt(end - 1) === "|") {
      end--;
      anchoredEnd = true;
    }
    if (!anchoredStart) {
      while (i < end && pattern.charAt(i) === "*") i++;
    }
    if (!anchoredEnd) {
      while (end > i && pattern.charAt(end - 1) === "*") end--;
    }
    for (; i < end; i++) {
      var c = pattern.charAt(i);
      if (c === "*") {
        if (re.slice(-2) !== ".*") re += ".*";
      } else if (c === "^") {
        re += SEPARATOR;
      } else if (c === "|") {
        return null; // WebKit has no alternation.
      } else if ("\\.+?{}()[]$/".indexOf(c) >= 0) {
        re += "\\" + c;
      } else {
        re += c;
      }
    }
    if (anchoredEnd) re += "$";
    if (re === "" || re === "^" || re === ".*") return ".*";
    return re;
  }

  function addFrameTypes(base, types, out) {
    var plain = [];
    var frames = false;
    for (var i = 0; i < types.length; i++) {
      var t = TYPE_MAP[types[i]];
      if (!t) continue;
      if (t === "subdocument") frames = true;
      else if (plain.indexOf(t) < 0) plain.push(t);
    }
    if (plain.length) {
      var a = JSON.parse(JSON.stringify(base));
      a.trigger["resource-type"] = plain;
      out.push(a);
    }
    if (frames) {
      var b = JSON.parse(JSON.stringify(base));
      b.trigger["resource-type"] = ["document"];
      b.trigger["load-context"] = ["child-frame"];
      out.push(b);
    }
  }

  return function convert(text) {
    var lines = String(text).split(/\r?\n/);
    var blocks = [];
    var exceptions = [];
    var pageAllow = { network: [], cosmetic: [] };
    var genericHide = Object.create(null); // selector -> true
    var genericExceptions = Object.create(null); // selector -> [domains] ("" = everywhere)
    var specificHide = Object.create(null); // "if:a.com,b.com" -> [selectors]
    var blockDomains = Object.create(null);
    var exceptionDomains = Object.create(null);
    var stats = { lines: lines.length, network: 0, exceptions: 0, cosmetic: 0, skipped: 0 };

    for (var n = 0; n < lines.length; n++) {
      var line = lines[n].trim();
      if (!line || line.charAt(0) === "!" || line.charAt(0) === "[") continue;

      // ---- Element hiding -------------------------------------------------
      var cm = COSMETIC.exec(line);
      if (cm) {
        var marker = cm[2];
        var selector = cm[3].trim();
        if ((marker !== "##" && marker !== "#@#") || PROCEDURAL.test(selector) || !isASCII(selector) ||
            selector.indexOf("+js(") === 0 || selector.charAt(0) === "+" || selector.charAt(0) === "^") {
          stats.skipped++;
          continue;
        }
        var cd = parseDomains(cm[1], ",");
        if (cd.dropped && !cd.include.length && !cd.exclude.length) { stats.skipped++; continue; }
        if (marker === "#@#") {
          var list = genericExceptions[selector] || (genericExceptions[selector] = []);
          if (!cd.include.length) list.push("");
          else list.push.apply(list, cd.include);
          continue;
        }
        if (!cd.include.length && !cd.exclude.length) {
          genericHide[selector] = true;
        } else if (cd.include.length) {
          var key = cd.include.sort().join(",");
          (specificHide[key] || (specificHide[key] = [])).push(selector);
        } else {
          var ukey = "unless:" + cd.exclude.sort().join(",");
          (specificHide[ukey] || (specificHide[ukey] = [])).push(selector);
        }
        stats.cosmetic++;
        continue;
      }

      // ---- Network filters ------------------------------------------------
      var isException = line.indexOf("@@") === 0;
      var body = isException ? line.slice(2) : line;

      if (body.charAt(0) === "/" && /\/(\$|$)/.test(body.slice(1))) { stats.skipped++; continue; } // regex filter

      var pattern = body;
      var optionText = "";
      var dollar = body.lastIndexOf("$");
      if (dollar >= 0 && /^[a-z0-9~_,=|.*:\-]+$/i.test(body.slice(dollar + 1))) {
        pattern = body.slice(0, dollar);
        optionText = body.slice(dollar + 1);
      }

      var loadType = null;
      var domains = { include: [], exclude: [], dropped: 0 };
      var types = [];
      var negatedTypes = [];
      var caseSensitive = false;
      var allowPage = false, allowCosmetic = false;
      var skip = false;

      if (optionText) {
        var options = optionText.split(",");
        for (var o = 0; o < options.length && !skip; o++) {
          var opt = options[o].trim().toLowerCase();
          var value = "";
          var eq = opt.indexOf("=");
          if (eq >= 0) { value = options[o].trim().slice(eq + 1); opt = opt.slice(0, eq); }
          if (IGNORED_OPTIONS[opt]) continue;
          if (opt === "third-party" || opt === "3p") loadType = "third-party";
          else if (opt === "~third-party" || opt === "1p" || opt === "first-party" || opt === "~3p") loadType = "first-party";
          else if (opt === "domain" || opt === "from") domains = parseDomains(value, "|");
          else if (opt === "match-case") caseSensitive = true;
          else if (opt === "document" || opt === "doc") { if (isException) allowPage = true; else types.push("document"); }
          else if (opt === "elemhide" || opt === "ehide" || opt === "generichide" || opt === "ghide") {
            if (isException) allowCosmetic = true; else skip = true;
          }
          else if (opt.charAt(0) === "~" && TYPE_MAP[opt.slice(1)]) negatedTypes.push(opt.slice(1));
          else if (TYPE_MAP[opt]) types.push(opt);
          else skip = true; // unsupported or unknown option
          if (UNSUPPORTED_OPTIONS[opt]) skip = true;
        }
      }
      if (skip || (domains.dropped && !domains.include.length && !domains.exclude.length)) { stats.skipped++; continue; }

      // Whole-site exceptions: @@||site.com^$document / $elemhide
      if (allowPage || allowCosmetic) {
        var m = /^\|\|([a-z0-9.-]+)\^?\|?$/.exec(pattern.toLowerCase());
        if (!m || !PLAIN_DOMAIN.test(m[1])) { stats.skipped++; continue; }
        var allow = { trigger: { "url-filter": ".*", "if-domain": ["*" + m[1]] }, action: { type: "ignore-previous-rules" } };
        if (allowPage) pageAllow.network.push(allow);
        pageAllow.cosmetic.push(allow);
        stats.exceptions++;
        continue;
      }

      var urlFilter = toURLFilter(pattern);
      if (!urlFilter) { stats.skipped++; continue; }
      if (urlFilter === ".*" && !domains.include.length && !types.length && !negatedTypes.length) {
        stats.skipped++; // would match everything
        continue;
      }

      var base = { trigger: { "url-filter": urlFilter }, action: { type: isException ? "ignore-previous-rules" : "block" } };
      if (caseSensitive) base.trigger["url-filter-is-case-sensitive"] = true;
      if (loadType) base.trigger["load-type"] = [loadType];
      if (domains.include.length) base.trigger["if-domain"] = star(domains.include);
      else if (domains.exclude.length) base.trigger["unless-domain"] = star(domains.exclude);

      var target = isException ? exceptions : blocks;
      var before = target.length;
      if (types.indexOf("document") >= 0) {
        var doc = JSON.parse(JSON.stringify(base));
        doc.trigger["resource-type"] = ["document"];
        doc.trigger["load-context"] = ["top-frame"];
        target.push(doc);
        types = types.filter(function (t) { return t !== "document"; });
        if (types.length) addFrameTypes(base, types, target);
      } else if (types.length) {
        addFrameTypes(base, types, target);
      } else if (negatedTypes.length) {
        addFrameTypes(base, ALL_TYPES.filter(function (t) { return negatedTypes.indexOf(t) < 0; }), target);
      } else {
        target.push(base);
      }
      if (target.length === before) { stats.skipped++; continue; }
      if (isException) stats.exceptions++; else stats.network++;

      // Plain "||domain^" filters also feed the "what was blocked" report.
      var dm = /^\|\|([a-z0-9.-]+)\^$/.exec(pattern.toLowerCase());
      if (dm && PLAIN_DOMAIN.test(dm[1]) && !domains.include.length && !types.length && !negatedTypes.length) {
        (isException ? exceptionDomains : blockDomains)[dm[1]] = true;
      }
    }

    // ---- Assemble cosmetic rules ------------------------------------------
    var cosmetic = [];
    var batch = [];
    function flush() {
      if (batch.length) {
        cosmetic.push({ trigger: { "url-filter": ".*" }, action: { type: "css-display-none", selector: batch.join(",") } });
        batch = [];
      }
    }
    Object.keys(genericHide).forEach(function (sel) {
      var ex = genericExceptions[sel];
      if (ex && ex.indexOf("") >= 0) return; // allowed everywhere
      if (ex && ex.length) {
        cosmetic.push({ trigger: { "url-filter": ".*", "unless-domain": star(ex) }, action: { type: "css-display-none", selector: sel } });
        return;
      }
      batch.push(sel);
      if (batch.length >= SELECTORS_PER_RULE) flush();
    });
    flush();
    Object.keys(specificHide).forEach(function (key) {
      var unless = key.indexOf("unless:") === 0;
      var ds = (unless ? key.slice(7) : key).split(",");
      var sels = specificHide[key].filter(function (sel) {
        var ex = genericExceptions[sel];
        return !(ex && (ex.indexOf("") >= 0 || (!unless && ds.every(function (d) { return ex.indexOf(d) >= 0; }))));
      });
      for (var s = 0; s < sels.length; s += SELECTORS_PER_RULE) {
        var trigger = { "url-filter": ".*" };
        trigger[unless ? "unless-domain" : "if-domain"] = star(ds);
        cosmetic.push({ trigger: trigger, action: { type: "css-display-none", selector: sels.slice(s, s + SELECTORS_PER_RULE).join(",") } });
      }
    });

    var network = blocks.slice(0, MAX_RULES - exceptions.length - pageAllow.network.length)
      .concat(exceptions, pageAllow.network);
    cosmetic = cosmetic.slice(0, MAX_RULES - pageAllow.cosmetic.length).concat(pageAllow.cosmetic);

    Object.keys(exceptionDomains).forEach(function (d) { delete blockDomains[d]; });
    stats.networkRules = network.length;
    stats.cosmeticRules = cosmetic.length;

    return JSON.stringify({
      version: NEUTRIN_CONVERTER_VERSION,
      networkJSON: JSON.stringify(network),
      cosmeticJSON: JSON.stringify(cosmetic),
      blockDomains: Object.keys(blockDomains),
      exceptionDomains: Object.keys(exceptionDomains),
      stats: stats,
    });
  };
})();

if (typeof module === "object") {
  module.exports = { neutrinConvertFilterList: neutrinConvertFilterList, NEUTRIN_CONVERTER_VERSION: NEUTRIN_CONVERTER_VERSION };
}
