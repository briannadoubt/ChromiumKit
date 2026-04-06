import Foundation
import ChromiumKit

final class AppSchemeHandler: URLSchemeHandling {
    func response(for request: URLRequest) throws -> URLSchemeResponse {
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>ChromiumKit Demo</title>
          <style>
            body {
              margin: 0;
              font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, sans-serif;
              background:
                radial-gradient(circle at top left, rgba(50, 119, 246, 0.18), transparent 28%),
                linear-gradient(180deg, #edf5ff 0%, #ffffff 72%);
              color: #15253d;
            }
            main {
              max-width: 820px;
              margin: 0 auto;
              padding: 72px 28px 96px;
            }
            .eyebrow {
              display: inline-flex;
              align-items: center;
              gap: 8px;
              padding: 8px 12px;
              border-radius: 999px;
              background: rgba(15, 74, 161, 0.10);
              color: #0f4aa1;
              font-size: 0.92rem;
              font-weight: 700;
              letter-spacing: 0.02em;
            }
            h1 {
              margin: 22px 0 16px;
              font-size: clamp(2.8rem, 5vw, 5.2rem);
              line-height: 0.94;
              max-width: 10ch;
            }
            p {
              max-width: 58ch;
              font-size: 1.06rem;
              line-height: 1.65;
            }
            .row {
              display: flex;
              flex-wrap: wrap;
              gap: 14px;
              margin-top: 28px;
            }
            button, a {
              appearance: none;
              border: 0;
              border-radius: 16px;
              padding: 14px 18px;
              font: inherit;
              text-decoration: none;
              cursor: pointer;
              transition: transform 140ms ease, box-shadow 140ms ease;
            }
            button:hover, a:hover {
              transform: translateY(-1px);
            }
            button {
              background: #0f4aa1;
              color: #fff;
              box-shadow: 0 16px 36px rgba(15, 74, 161, 0.22);
            }
            a {
              background: rgba(255, 255, 255, 0.88);
              color: #15253d;
              box-shadow: inset 0 0 0 1px rgba(21, 37, 61, 0.12);
            }
            .card {
              margin-top: 42px;
              padding: 24px 24px 22px;
              border-radius: 24px;
              background: rgba(255, 255, 255, 0.84);
              box-shadow: 0 28px 60px rgba(20, 49, 98, 0.12);
            }
            .grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
              gap: 16px;
              margin-top: 18px;
            }
            .metric {
              padding: 16px;
              border-radius: 18px;
              background: rgba(237, 245, 255, 0.86);
            }
            .metric strong {
              display: block;
              font-size: 1.6rem;
              margin-bottom: 4px;
            }
            code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            }
          </style>
        </head>
        <body>
          <main>
            <span class="eyebrow">ChromiumKit • SwiftUI-first CEF</span>
            <h1>Chromium, but shaped like modern Swift.</h1>
            <p>
              This page is served from a custom <code>app://</code> URL scheme handled in Swift,
              rendered by Chromium Embedded Framework, and embedded in a SwiftUI app through
              <code>WebPage</code> plus <code>WebView</code>.
            </p>
            <div class="row">
              <button id="titleButton">Change document.title</button>
              <a href="https://developer.apple.com/videos/play/wwdc2025/231/" target="_blank">Open WebKit for SwiftUI</a>
            </div>
            <section class="card">
              <h2>What this demo is exercising</h2>
              <div class="grid">
                <div class="metric">
                  <strong>SwiftUI</strong>
                  <span>Declarative host UI around Chromium.</span>
                </div>
                <div class="metric">
                  <strong>State</strong>
                  <span>Observable title, URL, loading, history, progress.</span>
                </div>
                <div class="metric">
                  <strong>JavaScript</strong>
                  <span>Async round-trips back into Swift.</span>
                </div>
                <div class="metric">
                  <strong>Routing</strong>
                  <span>Custom URL schemes and external-link decisions.</span>
                </div>
              </div>
            </section>
          </main>
          <script>
            document.getElementById("titleButton").addEventListener("click", () => {
              document.title = "ChromiumKit Demo @ " + new Date().toLocaleTimeString();
            });
          </script>
        </body>
        </html>
        """

        return URLSchemeResponse(
            data: Data(html.utf8),
            mimeType: "text/html",
            headers: ["Cache-Control": "no-store"]
        )
    }
}
