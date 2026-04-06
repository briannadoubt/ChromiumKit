import SwiftUI
import ChromiumKit

private let exampleURL = URL(string: "https://example.com")!
private let chromiumURL = URL(string: "https://www.chromium.org")!
private let localDemoURL = URL(string: "app://index.html")!

struct BrowserPlayground: View {
    @State private var coordinator: BrowserCoordinator
    @State private var page: WebPage
    @State private var javaScriptResult = "Tap “Inspect Title” to round-trip through JavaScript."

    init() {
        let coordinator = BrowserCoordinator()
        let configuration = WebPage.Configuration(
            profile: .ephemeral,
            navigationDecider: coordinator,
            permissionDecider: coordinator,
            urlSchemeHandlers: ["app": AppSchemeHandler()]
        )

        _coordinator = State(initialValue: coordinator)
        _page = State(initialValue: WebPage(url: exampleURL, configuration: configuration))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Example") {
                    try? page.load(URLRequest(url: exampleURL))
                }

                Button("Chromium") {
                    try? page.load(URLRequest(url: chromiumURL))
                }

                Button("Local Demo") {
                    try? page.load(URLRequest(url: localDemoURL))
                }

                Button("Back") { page.goBack() }
                    .disabled(!page.canGoBack)

                Button("Forward") { page.goForward() }
                    .disabled(!page.canGoForward)

                Button("Reload") { page.reload() }

                Button("Inspect Title") {
                    Task {
                        let title: String = (try? await page.callJavaScript("return document.title", as: String.self)) ?? "Unavailable"
                        await MainActor.run {
                            javaScriptResult = title
                        }
                    }
                }

                Spacer()

                if page.isLoading {
                    ProgressView(value: page.estimatedProgress)
                        .frame(width: 140)
                }
            }
            .padding()

            Divider()

            WebView(page)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(page.title ?? "No title yet")
                    .font(.headline)

                if let url = page.url {
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(javaScriptResult)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Last external URL: \(coordinator.lastExternalURL?.absoluteString ?? "None")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1100, minHeight: 760)
    }
}

final class BrowserCoordinator: NavigationDeciding, PermissionDeciding {
    var lastExternalURL: URL?

    func decidePolicy(for action: NavigationAction) -> NavigationDecision {
        guard action.url.scheme?.lowercased() != "app" else {
            return .allow
        }

        if action.opensNewWindow {
            lastExternalURL = action.url
            return .openExternally
        }

        return .allow
    }

    func decidePermission(for request: PermissionRequest) -> PermissionDecision {
        .default
    }
}
