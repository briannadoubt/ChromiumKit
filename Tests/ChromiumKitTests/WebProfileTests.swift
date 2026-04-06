import XCTest
@testable import ChromiumKit

final class WebProfileTests: XCTestCase {
    func testEphemeralProfileDoesNotCreateCachePath() {
        XCTAssertNil(WebProfile.ephemeral.resolvedCacheDirectoryURL(cacheRootDirectoryURL: nil))
    }

    func testSharedProfileUsesProfilesDefaultUnderCacheRoot() {
        let customRoot = URL(fileURLWithPath: "/tmp/ChromiumKitRoot", isDirectory: true)
        let path = WebProfile.default.resolvedCacheDirectoryURL(cacheRootDirectoryURL: customRoot)?.path
        XCTAssertNotNil(path)
        XCTAssertTrue(path?.hasSuffix("ChromiumKitRoot/Profiles/Default") == true)
    }

    func testDefaultCacheRootIncludesBundleIdentifierAndChromiumKitDirectory() {
        final class BundleToken {}
        let bundle = Bundle(for: BundleToken.self)

        let root = WebProfile.defaultCacheRootDirectoryURL(bundle: bundle)

        XCTAssertNotNil(root)
        XCTAssertTrue(root?.path.hasSuffix("\(bundle.bundleIdentifier ?? "ChromiumKitHost")/ChromiumKit") == true)
    }

    func testPersistentProfileUsesProvidedPath() {
        let expected = URL(fileURLWithPath: "/tmp/ChromiumKitProfile", isDirectory: true)
        let profile = WebProfile(storage: .persistent(expected))
        XCTAssertEqual(profile.resolvedCacheDirectoryURL(cacheRootDirectoryURL: nil), expected)
    }
}
