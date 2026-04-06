import Foundation
import Observation

@MainActor
@Observable
public final class WebPage {
    public enum NavigationEvent: Sendable, Equatable {
        case startedProvisionalNavigation(id: Int, url: URL?)
        case receivedServerRedirect(id: Int, url: URL?)
        case committed(id: Int, url: URL?)
        case finished(id: Int, url: URL?, httpStatusCode: Int)
        case failed(id: Int, url: URL?, error: NavigationFailure)
        case failedProvisionalNavigation(id: Int, url: URL?, error: NavigationFailure)
    }

    public struct NavigationFailure: Error, Sendable, Equatable {
        public var code: Int
        public var description: String
        public var url: URL?

        public init(code: Int, description: String, url: URL?) {
            self.code = code
            self.description = description
            self.url = url
        }
    }

    public struct Configuration {
        public var profile: WebProfile
        public var navigationDecider: (any NavigationDeciding)?
        public var permissionDecider: (any PermissionDeciding)?
        public var urlSchemeHandlers: [String: any URLSchemeHandling]

        public init(
            profile: WebProfile = .default,
            navigationDecider: (any NavigationDeciding)? = nil,
            permissionDecider: (any PermissionDeciding)? = nil,
            urlSchemeHandlers: [String: any URLSchemeHandling] = [:]
        ) {
            self.profile = profile
            self.navigationDecider = navigationDecider
            self.permissionDecider = permissionDecider
            self.urlSchemeHandlers = urlSchemeHandlers
        }
    }

    public private(set) var title: String?
    public private(set) var url: URL?
    public private(set) var isLoading = false
    public private(set) var estimatedProgress = 0.0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public private(set) var currentNavigationEvent: NavigationEvent?

    public let configuration: Configuration

    let bridge: BrowserBridgeController
    private var startupFailure: Error?

    public init(configuration: Configuration = .init()) {
        var startupFailure: Error?
        do {
            try ChromiumRuntime.registerKnownSchemes(configuration.urlSchemeHandlers.keys)
            try ChromiumRuntime.ensureInitialized()
        } catch {
            startupFailure = error
        }

        bridge = LiveBrowserBridgeController(configuration: configuration)
        self.configuration = configuration
        self.startupFailure = startupFailure
        bridge.delegate = self
    }

    public convenience init(url: URL, configuration: Configuration = .init()) {
        self.init(configuration: configuration)
        try? load(URLRequest(url: url))
    }

    public convenience init(request: URLRequest, configuration: Configuration = .init()) {
        self.init(configuration: configuration)
        try? load(request)
    }

    init(
        configuration: Configuration,
        bridge: BrowserBridgeController,
        startupFailure: Error? = nil
    ) {
        self.configuration = configuration
        self.bridge = bridge
        self.startupFailure = startupFailure
        bridge.delegate = self
    }

    public func load(_ request: URLRequest) throws {
        try ensureAvailable()
        try bridge.load(request)
    }

    public func loadHTML(_ html: String, baseURL: URL? = nil) throws {
        try ensureAvailable()
        try bridge.loadHTML(html, baseURL: baseURL)
    }

    public func load(data: Data, mimeType: String, characterEncoding: String = "utf-8", baseURL: URL? = nil) throws {
        try ensureAvailable()
        try bridge.load(data: data, mimeType: mimeType, characterEncoding: characterEncoding, baseURL: baseURL)
    }

    public func reload() {
        bridge.reload()
    }

    public func stopLoading() {
        bridge.stopLoading()
    }

    public func goBack() {
        bridge.goBack()
    }

    public func goForward() {
        bridge.goForward()
    }

    public func callJavaScript(_ javaScript: String) async throws -> JSONValue? {
        let data = try await callJavaScriptData(javaScript)
        guard let data else {
            return nil
        }
        return try JSONDecoder().decode(JavaScriptEnvelope.self, from: data).value
    }

    public func callJavaScript<T: Decodable>(
        _ javaScript: String,
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await callJavaScriptData(javaScript) ?? Data("null".utf8)
        let envelope = try decoder.decode(JavaScriptEnvelope.self, from: data)
        let payload = try JSONEncoder().encode(envelope.value ?? .null)
        return try decoder.decode(T.self, from: payload)
    }

    private func callJavaScriptData(_ javaScript: String) async throws -> Data? {
        try ensureAvailable()
        return try await withCheckedThrowingContinuation { continuation in
            bridge.callJavaScript(javaScript) { result in
                continuation.resume(with: result.flatMap { json in
                    guard let json else {
                        return .success(nil)
                    }
                    return .success(Data(json.utf8))
                })
            }
        }
    }

    private func ensureAvailable() throws {
        if let startupFailure {
            throw startupFailure
        }
    }
}

@MainActor
extension WebPage: BrowserBridgeControllerDelegate {
    func bridgeDidUpdateTitle(_ title: String?) {
        self.title = title
    }

    func bridgeDidUpdateURL(_ url: URL?) {
        self.url = url
    }

    func bridgeDidUpdateLoadingState(isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    func bridgeDidUpdateEstimatedProgress(_ progress: Double) {
        estimatedProgress = progress
    }

    func bridgeDidStartNavigation(id: Int, url: URL?, isRedirect: Bool) {
        currentNavigationEvent = isRedirect
            ? .receivedServerRedirect(id: id, url: url)
            : .startedProvisionalNavigation(id: id, url: url)
    }

    func bridgeDidCommitNavigation(id: Int, url: URL?) {
        currentNavigationEvent = .committed(id: id, url: url)
    }

    func bridgeDidFinishNavigation(id: Int, url: URL?, httpStatusCode: Int) {
        currentNavigationEvent = .finished(id: id, url: url, httpStatusCode: httpStatusCode)
    }

    func bridgeDidFailNavigation(id: Int, url: URL?, provisional: Bool, code: Int, description: String) {
        let failure = NavigationFailure(code: code, description: description, url: url)
        currentNavigationEvent = provisional
            ? .failedProvisionalNavigation(id: id, url: url, error: failure)
            : .failed(id: id, url: url, error: failure)
    }

    func bridgeDidEncounterRuntimeError(_ error: any Error) {
        startupFailure = error
    }
}

private struct JavaScriptEnvelope: Codable {
    var chromiumKitType: String
    var value: JSONValue?
}
