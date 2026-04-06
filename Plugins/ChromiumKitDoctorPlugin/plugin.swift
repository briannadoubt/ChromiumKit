import Foundation
import PackagePlugin

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin
#endif

@main
struct ChromiumKitDoctorPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let projectURL = try resolveProjectURL(in: context.package.directoryURL)
        try runTool(named: "ChromiumKitCLI", arguments: ["doctor", "--project", projectURL.path], context: context)
    }

    private func resolveProjectURL(in directoryURL: URL) throws -> URL {
        let projects = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xcodeproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let projectURL = projects.first else {
            throw PluginError("No Xcode project was found next to Package.swift. Run `swift run chromiumkit doctor --project /path/to/MyApp.xcodeproj` instead.")
        }
        guard projects.count == 1 else {
            let names = projects.map(\.lastPathComponent).joined(separator: ", ")
            throw PluginError("Multiple Xcode projects were found: \(names). Run `swift run chromiumkit doctor --project /path/to/YourApp.xcodeproj` instead.")
        }
        return projectURL
    }
}

#if canImport(XcodeProjectPlugin)
extension ChromiumKitDoctorPlugin: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        try runTool(
            named: "ChromiumKitCLI",
            arguments: ["doctor", "--project", context.xcodeProject.directoryURL.path],
            context: context
        )
    }
}
#endif

private func runTool(named toolName: String, arguments: [String], context: some Any) throws {
    let toolURL: URL
    switch context {
    case let context as PluginContext:
        toolURL = try context.tool(named: toolName).url
    #if canImport(XcodeProjectPlugin)
    case let context as XcodePluginContext:
        toolURL = try context.tool(named: toolName).url
    #endif
    default:
        throw PluginError("Unsupported plugin context.")
    }

    let process = Process()
    process.executableURL = toolURL
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw PluginError("ChromiumKit doctor failed.")
    }
}

private struct PluginError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
