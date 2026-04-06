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
          <title>ChromiumKit Showcase</title>
          <style>
            body {
              margin: 0;
              font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, sans-serif;
              background: linear-gradient(180deg, #eef5ff 0%, #ffffff 65%);
              color: #13233a;
            }
            main {
              max-width: 760px;
              margin: 0 auto;
              padding: 64px 24px 88px;
            }
            .badge {
              display: inline-block;
              padding: 8px 12px;
              border-radius: 999px;
              background: #d8e8ff;
              color: #0f4aa1;
              font-weight: 600;
              letter-spacing: 0.02em;
            }
            h1 {
              font-size: clamp(2.4rem, 5vw, 4.6rem);
              line-height: 0.95;
              margin: 20px 0 16px;
            }
            p {
              max-width: 54ch;
              font-size: 1.05rem;
              line-height: 1.6;
            }
            .actions {
              display: flex;
              gap: 12px;
              margin-top: 28px;
            }
            button, a {
              appearance: none;
              border: 0;
              border-radius: 14px;
              padding: 13px 18px;
              font: inherit;
              cursor: pointer;
              text-decoration: none;
            }
            button {
              background: #0f4aa1;
              color: white;
            }
            a {
              background: white;
              color: #13233a;
              box-shadow: inset 0 0 0 1px rgba(19, 35, 58, 0.15);
            }
            .card {
              margin-top: 40px;
              padding: 24px;
              border-radius: 22px;
              background: rgba(255, 255, 255, 0.88);
              box-shadow: 0 20px 60px rgba(20, 49, 98, 0.12);
            }
            code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            }
          </style>
        </head>
        <body>
          <main>
            <span class="badge">ChromiumKit + SwiftUI</span>
            <h1>Drop Chromium into a Mac app without dropping down to raw CEF.</h1>
            <p>
              This page is served by a custom <code>app://</code> URL scheme implemented in Swift,
              rendered by CEF, and embedded with a SwiftUI-first surface.
            </p>
            <div class="actions">
              <button id="titleButton">Update Title From JavaScript</button>
              <a href="https://developer.apple.com/videos/play/wwdc2025/231/" target="_blank">Open the WebKit for SwiftUI session</a>
            </div>
            <div class="card">
              <strong>What this demo exercises</strong>
              <p>
                Observable page state, external-link handling, custom scheme loading,
                and JavaScript round-trips.
              </p>
            </div>
          </main>
          <script>
            document.getElementById("titleButton").addEventListener("click", () => {
              document.title = "Title updated at " + new Date().toLocaleTimeString();
            });
          </script>
        </body>
        </html>
        """

        return URLSchemeResponse(
            data: Data(html.utf8),
            mimeType: "text/html",
            headers: [
                "Cache-Control": "no-store"
            ]
        )
    }
}
