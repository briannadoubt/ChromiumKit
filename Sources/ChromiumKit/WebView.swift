import SwiftUI

public struct WebView: NSViewRepresentable {
    public let page: WebPage

    public init(_ page: WebPage) {
        self.page = page
    }

    public init(url: URL, configuration: WebPage.Configuration = .init()) {
        page = WebPage(url: url, configuration: configuration)
    }

    public init(request: URLRequest, configuration: WebPage.Configuration = .init()) {
        page = WebPage(request: request, configuration: configuration)
    }

    public func makeNSView(context: Context) -> some NSView {
        page.bridgeView
    }

    public func updateNSView(_ nsView: NSViewType, context: Context) {}
}

@MainActor
private extension WebPage {
    var bridgeView: NSView {
        bridge.view
    }
}
