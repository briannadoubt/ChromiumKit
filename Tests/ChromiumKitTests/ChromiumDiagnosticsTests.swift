import XCTest
@testable import ChromiumKit

final class ChromiumDiagnosticsTests: XCTestCase {
    private let helperNames = [
        "ChromiumKitHelper",
        "ChromiumKitHelper (Renderer)",
        "ChromiumKitHelper (GPU)",
        "ChromiumKitHelper (Plugin)",
        "ChromiumKitHelper (Alerts)"
    ]

    func testDetectsMissingRuntimePieces() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

        let appURL = tempURL.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents/Frameworks", isDirectory: true),
            withIntermediateDirectories: true
        )

        let diagnostics = ChromiumDiagnostics.inspect(appBundleURL: appURL)
        XCTAssertEqual(diagnostics.filter { $0.severity == .error }.count, 11)
    }

    func testAcceptsValidBundleLayout() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

        let appURL = tempURL.appendingPathComponent("Example.app", isDirectory: true)
        let frameworksURL = appURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)

        try FileManager.default.createDirectory(
            at: frameworksURL.appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true),
            withIntermediateDirectories: true
        )
        for helperName in helperNames {
            let helperURL = frameworksURL.appendingPathComponent("\(helperName).app/Contents/MacOS", isDirectory: true)
            try FileManager.default.createDirectory(
                at: helperURL,
                withIntermediateDirectories: true
            )

            let helperExecutableURL = helperURL.appendingPathComponent(helperName, isDirectory: false)
            XCTAssertTrue(
                FileManager.default.createFile(
                    atPath: helperExecutableURL.path,
                    contents: Data(),
                    attributes: [.posixPermissions: 0o755]
                )
            )
        }

        let diagnostics = ChromiumDiagnostics.inspect(appBundleURL: appURL)
        XCTAssertEqual(diagnostics.filter { $0.severity == .error }.count, 0)
        XCTAssertEqual(diagnostics.filter { $0.severity == .info }.count, 11)
    }
}
