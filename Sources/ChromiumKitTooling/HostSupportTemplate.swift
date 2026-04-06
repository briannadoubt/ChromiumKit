import Foundation

public struct HostSupportPaths: Sendable, Hashable {
    public var directoryURL: URL
    public var scriptURL: URL
    public var helperAppURL: URL

    public init(directoryURL: URL, scriptURL: URL, helperAppURL: URL) {
        self.directoryURL = directoryURL
        self.scriptURL = scriptURL
        self.helperAppURL = helperAppURL
    }
}

public enum HostSupportTemplate {
    public static let defaultDirectoryName = "ChromiumKitHostSupport"

    public static func install(
        into projectDirectoryURL: URL,
        directoryName: String = defaultDirectoryName
    ) throws -> HostSupportPaths {
        let sourceTemplateURL = try templateDirectoryURL()
        let supportDirectoryURL = projectDirectoryURL.appendingPathComponent(directoryName, isDirectory: true)

        return try install(templateDirectoryURL: sourceTemplateURL, at: supportDirectoryURL)
    }

    public static func install(at supportDirectoryURL: URL) throws -> HostSupportPaths {
        let sourceTemplateURL = try templateDirectoryURL()
        return try install(templateDirectoryURL: sourceTemplateURL, at: supportDirectoryURL)
    }

    public static func templateDirectoryURL() throws -> URL {
        guard let resourceURL = Bundle.module.resourceURL else {
            throw ToolingError.message("ChromiumKit host support resources are unavailable in the current tool bundle.")
        }

        let templateURL = resourceURL.appendingPathComponent("ChromiumKitHostSupportTemplate", isDirectory: true)
        guard FileManager.default.fileExists(atPath: templateURL.path) else {
            throw ToolingError.message("ChromiumKit host support template was not packaged with the CLI.")
        }

        return templateURL
    }

    private static func install(templateDirectoryURL: URL, at supportDirectoryURL: URL) throws -> HostSupportPaths {
        try FileSystemSupport.ensureDirectory(at: supportDirectoryURL.deletingLastPathComponent())
        try FileSystemSupport.replaceDirectory(at: supportDirectoryURL, with: templateDirectoryURL)

        let scriptURL = supportDirectoryURL.appendingPathComponent("embed_cef.sh", isDirectory: false)
        let helperAppURL = supportDirectoryURL.appendingPathComponent("ChromiumKitHelper.app", isDirectory: true)

        guard FileManager.default.fileExists(atPath: helperAppURL.path) else {
            throw ToolingError.message("The embedded ChromiumKit helper template is missing from the package resources.")
        }

        try FileSystemSupport.makeExecutable(at: scriptURL)
        let helperExecutableURL = helperAppURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("ChromiumKitHelper", isDirectory: false)
        try FileSystemSupport.makeExecutable(at: helperExecutableURL)

        return HostSupportPaths(
            directoryURL: supportDirectoryURL,
            scriptURL: scriptURL,
            helperAppURL: helperAppURL
        )
    }
}
