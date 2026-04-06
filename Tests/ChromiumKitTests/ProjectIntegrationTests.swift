import Foundation
import XCTest
@testable import ChromiumKitTooling

final class ProjectIntegrationTests: XCTestCase {
    func testAvailableAppTargetsAreParsedFromPBXProj() throws {
        let projectURL = try makeProject(named: "FixtureProject", pbxprojContents: fixturePBXProj())

        let targets = try XcodeProjectIntegration.availableAppTargets(in: projectURL)

        XCTAssertEqual(targets, [XcodeAppTarget(name: "FixtureApp", productType: "com.apple.product-type.application")])
    }

    func testIntegrateInstallsManagedHostSupportAndReplacesLegacyPhase() throws {
        let projectURL = try makeProject(named: "FixtureProject", pbxprojContents: fixturePBXProj())

        let result = try XcodeProjectIntegration.integrate(projectURL: projectURL, targetName: "FixtureApp")
        let pbxprojContents = try String(
            contentsOf: projectURL.appendingPathComponent("project.pbxproj", isDirectory: false),
            encoding: .utf8
        )

        XCTAssertTrue(result.didMutateProject)
        XCTAssertTrue(result.removedLegacyRuntimePhase)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.supportPaths.directoryURL.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: result.supportPaths.scriptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.supportPaths.helperAppURL.path))
        XCTAssertTrue(pbxprojContents.contains("ChromiumKit Managed Runtime"))
        XCTAssertTrue(pbxprojContents.contains("ChromiumKitHostSupport/embed_cef.sh"))
        XCTAssertFalse(pbxprojContents.contains("Embed CEF Runtime"))
    }

    private func makeProject(named projectName: String, pbxprojContents: String) throws -> URL {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectURL = rootURL.appendingPathComponent("\(projectName).xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try pbxprojContents.write(
            to: projectURL.appendingPathComponent("project.pbxproj", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        return projectURL
    }

    private func fixturePBXProj() -> String {
        """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tclasses = {
        \t};
        \tobjectVersion = 77;
        \tobjects = {

        /* Begin PBXShellScriptBuildPhase section */
        \t\tBBBBBBBBBBBBBBBBBBBBBBBB /* Embed CEF Runtime */ = {
        \t\t\tisa = PBXShellScriptBuildPhase;
        \t\t\tbuildActionMask = 2147483647;
        \t\t\tfiles = (
        \t\t\t);
        \t\t\tinputFileListPaths = (
        \t\t\t);
        \t\t\tinputPaths = (
        \t\t\t);
        \t\t\tname = "Embed CEF Runtime";
        \t\t\toutputFileListPaths = (
        \t\t\t);
        \t\t\toutputPaths = (
        \t\t\t);
        \t\t\trunOnlyForDeploymentPostprocessing = 0;
        \t\t\tshellPath = /bin/sh;
        \t\t\tshellScript = "echo Chromium Embedded Framework ChromiumKitHelper";
        \t\t\tshowEnvVarsInLog = 0;
        \t\t};
        /* End PBXShellScriptBuildPhase section */

        /* Begin PBXNativeTarget section */
        \t\tAAAAAAAAAAAAAAAAAAAAAAAA /* FixtureApp */ = {
        \t\t\tisa = PBXNativeTarget;
        \t\t\tbuildConfigurationList = E20BD1091F5A091FF3932D44 /* Build configuration list for PBXNativeTarget "FixtureApp" */;
        \t\t\tbuildPhases = (
        \t\t\t\tBBBBBBBBBBBBBBBBBBBBBBBB /* Embed CEF Runtime */,
        \t\t\t);
        \t\t\tbuildRules = (
        \t\t\t);
        \t\t\tdependencies = (
        \t\t\t);
        \t\t\tname = FixtureApp;
        \t\t\tpackageProductDependencies = (
        \t\t\t);
        \t\t\tproductName = FixtureApp;
        \t\t\tproductReference = 111111111111111111111111 /* FixtureApp.app */;
        \t\t\tproductType = "com.apple.product-type.application";
        \t\t};
        \t\tCCCCCCCCCCCCCCCCCCCCCCCC /* FixtureLibrary */ = {
        \t\t\tisa = PBXNativeTarget;
        \t\t\tbuildConfigurationList = D0AD9E52172DA238A40BE247 /* Build configuration list for PBXNativeTarget "FixtureLibrary" */;
        \t\t\tbuildPhases = (
        \t\t\t);
        \t\t\tbuildRules = (
        \t\t\t);
        \t\t\tdependencies = (
        \t\t\t);
        \t\t\tname = FixtureLibrary;
        \t\t\tpackageProductDependencies = (
        \t\t\t);
        \t\t\tproductName = FixtureLibrary;
        \t\t\tproductReference = 222222222222222222222222 /* libFixtureLibrary.a */;
        \t\t\tproductType = "com.apple.product-type.library.static";
        \t\t};
        /* End PBXNativeTarget section */

        \t};
        \trootObject = 999999999999999999999999 /* Project object */;
        }
        """
    }
}
