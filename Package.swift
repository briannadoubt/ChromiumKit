// swift-tools-version: 6.2

import PackageDescription
import Foundation

private struct CEFArtifactReleaseMetadata: Decodable {
    var version: String
    var url: String
    var checksum: String
}

private let fileManager = FileManager.default
private let packageRootURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let localCEFArtifactPath = packageRootURL
    .appendingPathComponent("Artifacts", isDirectory: true)
    .appendingPathComponent("ChromiumEmbeddedFramework.xcframework", isDirectory: true)
private let releaseMetadataURL = packageRootURL
    .appendingPathComponent("Config", isDirectory: true)
    .appendingPathComponent("cef-artifact-release.json", isDirectory: false)

private let useLocalCEFArtifact = ProcessInfo.processInfo.environment["CHROMIUMKIT_USE_LOCAL_CEF_ARTIFACT"] != "0"
    && fileManager.fileExists(atPath: localCEFArtifactPath.path)

private let releaseMetadata: CEFArtifactReleaseMetadata = {
    guard
        let data = try? Data(contentsOf: releaseMetadataURL),
        let metadata = try? JSONDecoder().decode(CEFArtifactReleaseMetadata.self, from: data)
    else {
        fatalError("Missing or invalid CEF artifact release metadata at \(releaseMetadataURL.path)")
    }
    return metadata
}()

private let cefBinaryTarget: Target = {
    if useLocalCEFArtifact {
        return .binaryTarget(
            name: "ChromiumEmbeddedFramework",
            path: "Artifacts/ChromiumEmbeddedFramework.xcframework"
        )
    }

    return .binaryTarget(
        name: "ChromiumEmbeddedFramework",
        url: releaseMetadata.url,
        checksum: releaseMetadata.checksum
    )
}()

let package = Package(
    name: "ChromiumKit",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "ChromiumKit",
            targets: ["ChromiumKit"]
        ),
        .executable(
            name: "chromiumkit",
            targets: ["ChromiumKitCLI"]
        ),
        .plugin(
            name: "ChromiumKitPlugin",
            targets: [
                "ChromiumKitIntegratePlugin",
                "ChromiumKitDoctorPlugin",
                "ChromiumKitRepairPlugin"
            ]
        )
    ],
    targets: [
        cefBinaryTarget,
        .target(
            name: "CEFDllWrapper",
            dependencies: [],
            path: "Vendor/CEF/libcef_dll",
            exclude: [
                "CMakeLists.txt",
                "cpptoc/test",
                "ctocpp/test",
                "wrapper/cef_scoped_library_loader_mac.mm",
                "wrapper/cef_scoped_sandbox_context_mac.mm",
                "wrapper/libcef_dll_dylib.cc"
            ],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath(".."),
                .unsafeFlags([
                    "-std=c++20",
                    "-DWRAPPING_CEF_SHARED"
                ])
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "ChromiumKitBridge",
            dependencies: [
                "CEFDllWrapper",
                "ChromiumEmbeddedFramework"
            ],
            path: "Sources/ChromiumKitBridge",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../Vendor/CEF")
            ],
            cxxSettings: [
                .headerSearchPath("../../Vendor/CEF"),
                .unsafeFlags(["-fobjc-arc", "-std=c++20"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../../Artifacts/ChromiumEmbeddedFramework.xcframework/macos-arm64_x86_64",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../../../../../Artifacts/ChromiumEmbeddedFramework.xcframework/macos-arm64_x86_64",
                    "-F", "Artifacts/ChromiumEmbeddedFramework.xcframework/macos-arm64_x86_64",
                    "-framework", "Chromium Embedded Framework"
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "ChromiumKit",
            dependencies: ["ChromiumKitBridge"],
            path: "Sources/ChromiumKit"
        ),
        .target(
            name: "ChromiumKitTooling",
            dependencies: [],
            path: "Sources/ChromiumKitTooling",
            resources: [
                .copy("Resources/ChromiumKitHostSupportTemplate")
            ]
        ),
        .executableTarget(
            name: "ChromiumKitCLI",
            dependencies: [
                "ChromiumKitTooling"
            ],
            path: "Sources/ChromiumKitCLI"
        ),
        .plugin(
            name: "ChromiumKitIntegratePlugin",
            capability: .command(
                intent: .custom(
                    verb: "integrate",
                    description: "Integrate ChromiumKit into the current Xcode project."
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "ChromiumKit needs to generate managed host-support files and update the project build phase."
                    )
                ]
            ),
            dependencies: [
                "ChromiumKitCLI"
            ],
            path: "Plugins/ChromiumKitIntegratePlugin"
        ),
        .plugin(
            name: "ChromiumKitDoctorPlugin",
            capability: .command(
                intent: .custom(
                    verb: "doctor",
                    description: "Validate ChromiumKit project and runtime integration."
                )
            ),
            dependencies: [
                "ChromiumKitCLI"
            ],
            path: "Plugins/ChromiumKitDoctorPlugin"
        ),
        .plugin(
            name: "ChromiumKitRepairPlugin",
            capability: .command(
                intent: .custom(
                    verb: "repair",
                    description: "Repair ChromiumKit managed files and project integration."
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "ChromiumKit needs to refresh managed host-support files and update the project build phase."
                    )
                ]
            ),
            dependencies: [
                "ChromiumKitCLI"
            ],
            path: "Plugins/ChromiumKitRepairPlugin"
        ),
        .testTarget(
            name: "ChromiumKitTests",
            dependencies: [
                "ChromiumKit",
                "ChromiumKitTooling"
            ],
            path: "Tests/ChromiumKitTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
