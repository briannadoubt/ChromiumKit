import Foundation
import XCTest
@testable import ChromiumKitTooling

final class ReleasePreparationTests: XCTestCase {
    func testPrepareReleaseRefreshesChecksumAndReleaseURL() throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let artifactsURL = rootURL.appendingPathComponent("Artifacts", isDirectory: true)
        let xcframeworkURL = artifactsURL.appendingPathComponent("ChromiumEmbeddedFramework.xcframework", isDirectory: true)
        let libraryURL = xcframeworkURL
            .appendingPathComponent("macos-arm64_x86_64", isDirectory: true)
            .appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)
        let metadataURL = rootURL
            .appendingPathComponent("Config", isDirectory: true)
            .appendingPathComponent("cef-artifact-release.json", isDirectory: false)

        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stub".utf8).write(to: libraryURL.appendingPathComponent("Chromium Embedded Framework", isDirectory: false))
        try Data(
            """
            {
              "version": "1.2.3",
              "url": "https://example.invalid/old.zip",
              "checksum": "0000000000000000000000000000000000000000000000000000000000000000"
            }
            """.utf8
        ).write(to: metadataURL)

        let result = try ReleasePreparation.prepareRelease(
            packageRootURL: rootURL,
            releaseURL: "https://github.com/example/repo/releases/download/cef-1.2.3/ChromiumEmbeddedFramework.xcframework.zip"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.archiveURL.path))
        XCTAssertFalse(result.checksum.isEmpty)

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: String]
        XCTAssertEqual(
            metadata?["url"],
            "https://github.com/example/repo/releases/download/cef-1.2.3/ChromiumEmbeddedFramework.xcframework.zip"
        )
        XCTAssertEqual(metadata?["checksum"], result.checksum)
    }
}
