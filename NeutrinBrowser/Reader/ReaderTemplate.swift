import Foundation

/// Builds the HTML page shown in reader mode.
///
/// The reader web view runs with page JavaScript disabled and a strict
/// Content-Security-Policy, so article markup can't run scripts.
enum ReaderTemplate {
    static func html(for article: ReaderArticle, settings: ReaderSettings) -> String {
        let host = article.url?.displayHost ?? ""
        let label = (article.siteName?.isEmpty == false ? article.siteName! : host)
        var meta = ["\(article.minutesToRead) min de lectura"]
        if let byline = article.byline, !byline.isEmpty { meta.insert(byline, at: 0) }
        if !host.isEmpty { meta.append(host) }

        let excerpt = article.excerpt.flatMap { text -> String? in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Readability often uses the first paragraph as the excerpt; skip it then.
            guard !trimmed.isEmpty, !(article.content ?? "").contains(trimmed.prefix(80)) else { return nil }
            return trimmed
        }

        return """
        <!doctype html>
        <html lang="es" data-neutrin-reader="1" data-theme="\(settings.theme.rawValue)" data-font="\(settings.font.rawValue)" style="--font-size:\(Int(settings.fontSize))px">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; media-src https:; style-src 'unsafe-inline'; font-src https: data:">
        <meta name="referrer" content="no-referrer">
        <title>\(escape(article.title ?? ""))</title>
        <style>\(css)</style>
        </head>
        <body>
        <main>
          <header>
            \(label.isEmpty ? "" : "<p class=\"label\">\(escape(label))</p>")
            <h1>\(escape(article.title ?? host))</h1>
            \(excerpt.map { "<p class=\"excerpt\">\(escape($0))</p>" } ?? "")
            <p class="meta">\(meta.map(escape).joined(separator: " &middot; "))</p>
          </header>
          <article>\(article.content ?? "")</article>
        </main>
        </body>
        </html>
        """
    }

    /// JavaScript the app runs (page JS stays off) to restyle without reloading.
    static func applySettingsScript(_ settings: ReaderSettings) -> String {
        """
        (function(){var r=document.documentElement;
        r.dataset.theme='\(settings.theme.rawValue)';
        r.dataset.font='\(settings.font.rawValue)';
        r.style.setProperty('--font-size','\(Int(settings.fontSize))px');})();
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let css = """
    :root{--bg:#f7f8fc;--fg:#1c1d21;--muted:#6b6f7b;--accent:#2b6bf5;--rule:rgba(0,0,0,.08);color-scheme:light dark}
    html[data-theme=light]{--bg:#f7f8fc;--fg:#1c1d21;--muted:#6b6f7b;--accent:#2b6bf5;--rule:rgba(0,0,0,.08)}
    html[data-theme=sepia]{--bg:#f6efe2;--fg:#43352a;--muted:#86725f;--accent:#a3561f;--rule:rgba(67,53,42,.14)}
    html[data-theme=dark]{--bg:#111318;--fg:#e4e6eb;--muted:#9096a3;--accent:#6aa6ff;--rule:rgba(255,255,255,.1)}
    @media (prefers-color-scheme:dark){html[data-theme=auto]{--bg:#111318;--fg:#e4e6eb;--muted:#9096a3;--accent:#6aa6ff;--rule:rgba(255,255,255,.1)}}
    html{background:var(--bg);-webkit-text-size-adjust:100%}
    body{margin:0;background:var(--bg);color:var(--fg);font-size:var(--font-size);line-height:1.6;
      font-family:ui-serif,"New York",Georgia,serif;-webkit-font-smoothing:antialiased}
    html[data-font=sans] body{font-family:-apple-system,system-ui,"Helvetica Neue",sans-serif}
    main{max-width:680px;margin:0 auto;padding:28px 22px 120px}
    header{margin-bottom:28px;padding-bottom:22px;border-bottom:1px solid var(--rule)}
    .label{margin:0 0 10px;font:700 13px/1.2 -apple-system,system-ui,sans-serif;letter-spacing:.12em;text-transform:uppercase;color:var(--accent)}
    h1{margin:0 0 12px;font:800 1.65em/1.15 -apple-system,system-ui,sans-serif;letter-spacing:-.01em}
    .excerpt{margin:0 0 12px;font-size:1.05em;color:var(--muted)}
    .meta{margin:0;font:500 14px/1.4 -apple-system,system-ui,sans-serif;color:var(--muted)}
    article h2,article h3,article h4{font-family:-apple-system,system-ui,sans-serif;line-height:1.25;margin:1.6em 0 .5em}
    article p{margin:0 0 1.1em}
    article a{color:var(--accent);text-decoration:none}
    article img,article video,article figure{max-width:100%;height:auto;border-radius:14px}
    article figure{margin:1.4em 0}
    article figcaption{font-size:.8em;color:var(--muted);margin-top:.5em}
    article blockquote{margin:1.2em 0;padding:.2em 0 .2em 1em;border-left:3px solid var(--accent);color:var(--muted)}
    article pre,article code{font-family:ui-monospace,Menlo,monospace;font-size:.85em}
    article pre{overflow-x:auto;padding:1em;border-radius:12px;background:var(--rule)}
    article table{display:block;overflow-x:auto;border-collapse:collapse;font-size:.85em}
    article td,article th{border:1px solid var(--rule);padding:.4em .6em}
    article hr{border:0;border-top:1px solid var(--rule);margin:2em 0}
    """
}
