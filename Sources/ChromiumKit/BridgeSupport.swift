import AppKit
@preconcurrency import ChromiumKitBridge
import Foundation

@MainActor
protocol BrowserBridgeControllerDelegate: AnyObject {
    func bridgeDidUpdateTitle(_ title: String?)
    func bridgeDidUpdateURL(_ url: URL?)
    func bridgeDidUpdateLoadingState(isLoading: Bool, canGoBack: Bool, canGoForward: Bool)
    func bridgeDidUpdateEstimatedProgress(_ progress: Double)
    func bridgeDidStartNavigation(id: Int, url: URL?, isRedirect: Bool)
    func bridgeDidCommitNavigation(id: Int, url: URL?)
    func bridgeDidFinishNavigation(id: Int, url: URL?, httpStatusCode: Int)
    func bridgeDidFailNavigation(id: Int, url: URL?, provisional: Bool, code: Int, description: String)
    func bridgeDidEncounterRuntimeError(_ error: Error)
}

@MainActor
protocol BrowserBridgeController: AnyObject {
    var view: NSView { get }
    var delegate: BrowserBridgeControllerDelegate? { get set }

    func load(_ request: URLRequest) throws
    func loadHTML(_ html: String, baseURL: URL?) throws
    func load(data: Data, mimeType: String, characterEncoding: String, baseURL: URL?) throws
    func reload()
    func stopLoading()
    func goBack()
    func goForward()
    func callJavaScript(_ javaScript: String, completion: @escaping @Sendable (Result<String?, Error>) -> Void)
}

@MainActor
final class LiveBrowserBridgeController: NSObject, BrowserBridgeController {
    weak var delegate: BrowserBridgeControllerDelegate?

    private let navigationAdapter: NavigationDeciderAdapter?
    private let permissionAdapter: PermissionDeciderAdapter?
    private let schemeAdapters: [String: URLSchemeHandlerAdapter]
    private let controller: CKWebViewHostController

    var view: NSView {
        controller.view
    }

    init(configuration: WebPage.Configuration) {
        navigationAdapter = configuration.navigationDecider.map(NavigationDeciderAdapter.init)
        permissionAdapter = configuration.permissionDecider.map(PermissionDeciderAdapter.init)
        schemeAdapters = configuration.urlSchemeHandlers.mapValues(URLSchemeHandlerAdapter.init)

        let bridgeConfiguration = CKWebPageConfiguration()
        bridgeConfiguration.cacheDirectoryURL = ChromiumRuntime.resolvedCacheDirectoryURL(for: configuration.profile)
        bridgeConfiguration.navigationDecider = navigationAdapter
        bridgeConfiguration.permissionDecider = permissionAdapter
        bridgeConfiguration.urlSchemeHandlers = schemeAdapters
        controller = CKWebViewHostController(configuration: bridgeConfiguration)

        super.init()

        controller.delegate = self
    }

    func load(_ request: URLRequest) throws {
        try controller.load(request)
    }

    func loadHTML(_ html: String, baseURL: URL?) throws {
        try controller.loadHTMLString(html, baseURL: baseURL)
    }

    func load(data: Data, mimeType: String, characterEncoding: String, baseURL: URL?) throws {
        try controller.load(data, mimeType: mimeType, characterEncoding: characterEncoding, baseURL: baseURL)
    }

    func reload() {
        controller.reload()
    }

    func stopLoading() {
        controller.stopLoading()
    }

    func goBack() {
        controller.goBack()
    }

    func goForward() {
        controller.goForward()
    }

    func callJavaScript(_ javaScript: String, completion: @escaping @Sendable (Result<String?, Error>) -> Void) {
        controller.evaluateJavaScript(javaScript) { json, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(json))
            }
        }
    }
}

extension LiveBrowserBridgeController: CKWebViewHostControllerDelegate {
    nonisolated func webViewHostController(_ controller: CKWebViewHostController, didUpdateTitle title: String?) {
        Task { @MainActor in
            delegate?.bridgeDidUpdateTitle(title)
        }
    }

    nonisolated func webViewHostController(_ controller: CKWebViewHostController, didUpdate url: URL?) {
        Task { @MainActor in
            delegate?.bridgeDidUpdateURL(url)
        }
    }

    nonisolated func webViewHostController(_ controller: CKWebViewHostController, didUpdateLoadingState isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        Task { @MainActor in
            delegate?.bridgeDidUpdateLoadingState(isLoading: isLoading, canGoBack: canGoBack, canGoForward: canGoForward)
        }
    }

    nonisolated func webViewHostController(_ controller: CKWebViewHostController, didUpdateEstimatedProgress progress: Double) {
        Task { @MainActor in
            delegate?.bridgeDidUpdateEstimatedProgress(progress)
        }
    }

    nonisolated func webViewHostController(_ controller: CKWebViewHostController, didStartNavigationWithID identifier: Int, url: URL?, isRedirect: Bool) {
        Task { @MainActor in
            delegate?.bridgeDidStartNavigation(id: identifier, url: url, isRedirect: isRedirect)
        }
    }

    nonisolated func webViewHostController(_ controller: CKWebViewHostController, didCommitNavigationWithID identifier: Int, url: URL?) {
        Task { @MainActor in
            delegate?.bridgeDidCommitNavigation(id: identifier, url: url)
        }
    }

    nonisolated func webViewHostController(_ controller: CKWebViewHostController, didFinishNavigationWithID identifier: Int, url: URL?, httpStatusCode: Int) {
        Task { @MainActor in
            delegate?.bridgeDidFinishNavigation(id: identifier, url: url, httpStatusCode: httpStatusCode)
        }
    }

    nonisolated func webViewHostController(_ controller: CKWebViewHostController, didFailNavigationWithID identifier: Int, url: URL?, provisional: Bool, code: Int, description: String) {
        Task { @MainActor in
            delegate?.bridgeDidFailNavigation(id: identifier, url: url, provisional: provisional, code: code, description: description)
        }
    }

    nonisolated func webViewHostController(_ controller: CKWebViewHostController, didEncounterRuntimeError error: any Error) {
        Task { @MainActor in
            delegate?.bridgeDidEncounterRuntimeError(error)
        }
    }
}

private final class NavigationDeciderAdapter: NSObject, CKNavigationDeciding {
    private weak var base: (any NavigationDeciding)?

    init(_ base: any NavigationDeciding) {
        self.base = base
    }

    func decidePolicy(for action: CKNavigationAction) -> CKNavigationDecision {
        guard let base, let url = action.url else {
            return .allow
        }

        let decision = base.decidePolicy(
            for: NavigationAction(
                url: url,
                isUserGesture: action.isUserGesture,
                isRedirect: action.isRedirect,
                opensNewWindow: action.opensNewWindow
            )
        )

        switch decision {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case .openExternally:
            return .openExternally
        }
    }
}

private final class PermissionDeciderAdapter: NSObject, CKPermissionDeciding {
    private weak var base: (any PermissionDeciding)?

    init(_ base: any PermissionDeciding) {
        self.base = base
    }

    func decidePermission(for request: CKPermissionRequest) -> CKPermissionDecision {
        let origin = request.origin.flatMap(URL.init(string:))
        let swiftRequest = PermissionRequest(origin: origin, kinds: .init(rawValue: UInt(request.kinds.rawValue)))

        switch base?.decidePermission(for: swiftRequest) ?? .default {
        case .allow:
            return .allow
        case .deny:
            return .deny
        case .default:
            return .default
        }
    }
}

private final class URLSchemeHandlerAdapter: NSObject, CKURLSchemeHandling {
    private weak var base: (any URLSchemeHandling)?

    init(_ base: any URLSchemeHandling) {
        self.base = base
    }

    func response(for request: URLRequest) throws -> CKURLSchemeResponse {
        guard let base else {
            throw ChromiumError.runtimeUnavailable("URL scheme handler was deallocated before Chromium requested a resource.")
        }
        let response = try base.response(for: request)
        return CKURLSchemeResponse(
            body: response.data,
            mimeType: response.mimeType,
            statusCode: response.statusCode,
            headers: response.headers
        )
    }
}
