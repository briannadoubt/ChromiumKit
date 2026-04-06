import SwiftUI
import ChromiumKit

struct ContentView: View {
    @State private var page = WebPage(url: URL(string: "https://www.chromium.org")!)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Back") { page.goBack() }
                    .disabled(!page.canGoBack)

                Button("Forward") { page.goForward() }
                    .disabled(!page.canGoForward)

                Button("Reload") { page.reload() }

                Spacer()

                if page.isLoading {
                    ProgressView(value: page.estimatedProgress)
                        .frame(width: 140)
                }
            }
            .padding()

            Divider()

            WebView(page)
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}
