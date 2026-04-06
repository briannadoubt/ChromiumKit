import Foundation

private struct ReleaseArtifactMetadata: Codable {
    var version: String
    var url: String
    var checksum: String
}

public struct ReleasePreparationResult: Sendable, Hashable {
    public var archiveURL: URL
    public var checksum: String
    public var metadataURL: URL

    public init(archiveURL: URL, checksum: String, metadataURL: URL) {
        self.archiveURL = archiveURL
        self.checksum = checksum
        self.metadataURL = metadataURL
    }
}

public enum ReleasePreparation {
    public static func prepareRelease(
        packageRootURL: URL,
        artifactsDirectoryName: String = "Artifacts",
        releaseURL: String? = nil
    ) throws -> ReleasePreparationResult {
        let artifactsDirectoryURL = packageRootURL.appendingPathComponent(artifactsDirectoryName, isDirectory: true)
        let xcframeworkURL = artifactsDirectoryURL.appendingPathComponent("ChromiumEmbeddedFramework.xcframework", isDirectory: true)
        let distDirectoryURL = packageRootURL.appendingPathComponent("Dist", isDirectory: true)
        let archiveURL = distDirectoryURL.appendingPathComponent("ChromiumEmbeddedFramework.xcframework.zip", isDirectory: false)
        let metadataURL = packageRootURL
            .appendingPathComponent("Config", isDirectory: true)
            .appendingPathComponent("cef-artifact-release.json", isDirectory: false)

        guard FileManager.default.fileExists(atPath: xcframeworkURL.path) else {
            throw ToolingError.message("Missing ChromiumEmbeddedFramework.xcframework at \(xcframeworkURL.path). Run scripts/build_cef_artifact.sh first.")
        }

        try FileSystemSupport.ensureDirectory(at: distDirectoryURL)
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }

        let dittoResult = try ToolingProcess.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: [
                "-c",
                "-k",
                "--sequesterRsrc",
                "--keepParent",
                xcframeworkURL.path,
                archiveURL.path
            ],
            currentDirectoryURL: packageRootURL
        )

        guard dittoResult.exitStatus == 0 else {
            throw ToolingError.message("Failed to zip the CEF xcframework: \(dittoResult.standardError)")
        }

        let checksumResult = try ToolingProcess.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["package", "compute-checksum", archiveURL.path],
            currentDirectoryURL: packageRootURL
        )

        guard checksumResult.exitStatus == 0 else {
            throw ToolingError.message("swift package compute-checksum failed: \(checksumResult.standardError)")
        }

        let checksum = checksumResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        var metadata = try loadMetadata(from: metadataURL)
        if let releaseURL, !releaseURL.isEmpty {
            metadata.url = releaseURL
        }
        metadata.checksum = checksum
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL, options: .atomic)

        return ReleasePreparationResult(
            archiveURL: archiveURL,
            checksum: checksum,
            metadataURL: metadataURL
        )
    }

    private static func loadMetadata(from url: URL) throws -> ReleaseArtifactMetadata {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ReleaseArtifactMetadata.self, from: data)
    }
}
