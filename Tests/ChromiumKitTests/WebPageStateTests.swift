import AppKit
import XCTest
@testable import ChromiumKit

@MainActor
final class WebPageStateTests: XCTestCase {
    func testNavigationEventsUpdateObservableState() {
        let bridge = MockBrowserBridgeController()
        let page = WebPage(configuration: .init(), bridge: bridge)
        let url = URL(string: "https://example.com/article")!

        bridge.delegate?.bridgeDidStartNavigation(id: 7, url: url, isRedirect: false)
        XCTAssertEqual(page.currentNavigationEvent, .startedProvisionalNavigation(id: 7, url: url))

        bridge.delegate?.bridgeDidCommitNavigation(id: 7, url: url)
        XCTAssertEqual(page.currentNavigationEvent, .committed(id: 7, url: url))

        bridge.delegate?.bridgeDidFinishNavigation(id: 7, url: url, httpStatusCode: 200)
        XCTAssertEqual(page.currentNavigationEvent, .finished(id: 7, url: url, httpStatusCode: 200))
    }

    func testLoadingStateMirrorsBridgeCallbacks() {
        let bridge = MockBrowserBridgeController()
        let page = WebPage(configuration: .init(), bridge: bridge)

        bridge.delegate?.bridgeDidUpdateLoadingState(isLoading: true, canGoBack: true, canGoForward: false)
        bridge.delegate?.bridgeDidUpdateEstimatedProgress(0.6)
        bridge.delegate?.bridgeDidUpdateTitle("Fixture")

        XCTAssertTrue(page.isLoading)
        XCTAssertTrue(page.canGoBack)
        XCTAssertFalse(page.canGoForward)
        XCTAssertEqual(page.estimatedProgress, 0.6, accuracy: 0.0001)
        XCTAssertEqual(page.title, "Fixture")
    }

    func testCallJavaScriptDecodesTypedValue() async throws {
        struct Payload: Decodable, Equatable {
            var title: String
            var count: Int
        }

        let bridge = MockBrowserBridgeController()
        bridge.javaScriptResult = .success(#"{"chromiumKitType":"value","value":{"title":"Hello","count":3}}"#)
        let page = WebPage(configuration: .init(), bridge: bridge)

        let payload = try await page.callJavaScript("return { title: 'Hello', count: 3 }", as: Payload.self)
        XCTAssertEqual(payload, Payload(title: "Hello", count: 3))
    }

    func testStartupFailureIsThrownOnLoad() {
        let bridge = MockBrowserBridgeController()
        let page = WebPage(
            configuration: .init(),
            bridge: bridge,
            startupFailure: ChromiumError.runtimeUnavailable("Helper missing.")
        )

        XCTAssertThrowsError(try page.load(URLRequest(url: URL(string: "https://example.com")!)))
    }
}

@MainActor
private final class MockBrowserBridgeController: BrowserBridgeController {
    weak var delegate: BrowserBridgeControllerDelegate?
    let view = NSView()
    var javaScriptResult: Result<String?, Error> = .success(nil)

    func load(_ request: URLRequest) throws {}
    func loadHTML(_ html: String, baseURL: URL?) throws {}
    func load(data: Data, mimeType: String, characterEncoding: String, baseURL: URL?) throws {}
    func reload() {}
    func stopLoading() {}
    func goBack() {}
    func goForward() {}

    func callJavaScript(_ javaScript: String, completion: @escaping @Sendable (Result<String?, Error>) -> Void) {
        completion(javaScriptResult)
    }
}
