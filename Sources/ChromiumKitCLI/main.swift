import ChromiumKitTooling
import Foundation

@main
struct ChromiumKitCLI {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("chromiumkit: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
    }

    private static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            return
        }

        switch command {
        case "doctor":
            try runDoctor(arguments: Array(arguments.dropFirst()))
        case "check-runtime":
            try runRuntimeDoctor(arguments: Array(arguments.dropFirst()))
        case "integrate":
            try runIntegrate(arguments: Array(arguments.dropFirst()))
        case "repair":
            try runRepair(arguments: Array(arguments.dropFirst()))
        case "new-host":
            try runNewHost(arguments: Array(arguments.dropFirst()))
        case "prepare-release":
            try runPrepareRelease(arguments: Array(arguments.dropFirst()))
        default:
            throw ToolingError.message("Unknown command: \(command)")
        }
    }

    private static func runDoctor(arguments: [String]) throws {
        if let projectPath = try parseFlag("--project", from: arguments) {
            try printDiagnostics(
                XcodeProjectIntegration.inspectProject(
                    projectURL: URL(fileURLWithPath: projectPath),
                    targetName: try parseFlag("--target", from: arguments)
                )
            )
            return
        }

        if let path = arguments.first, path.hasSuffix(".xcodeproj") {
            try printDiagnostics(
                XcodeProjectIntegration.inspectProject(
                    projectURL: URL(fileURLWithPath: path),
                    targetName: try parseFlag("--target", from: arguments)
                )
            )
            return
        }

        try runRuntimeDoctor(arguments: arguments)
    }

    private static func runRuntimeDoctor(arguments: [String]) throws {
        let bundlePath = try parseFlag("--app", from: arguments) ?? arguments.first ?? Bundle.main.bundlePath
        let appBundleURL = URL(fileURLWithPath: bundlePath)
        let diagnostics = BundleDiagnostics.inspect(appBundleURL: appBundleURL)
            + BundleDiagnostics.inspectReleaseReadiness(appBundleURL: appBundleURL)
        diagnostics.forEach { diagnostic in
            let prefix = diagnostic.severity.rawValue.uppercased()
            if let path = diagnostic.path?.path {
                print("[\(prefix)] \(diagnostic.message) (\(path))")
            } else {
                print("[\(prefix)] \(diagnostic.message)")
            }
        }
    }

    private static func runIntegrate(arguments: [String]) throws {
        let projectPath = try parseRequiredFlag("--project", from: arguments)
        let result = try XcodeProjectIntegration.integrate(
            projectURL: URL(fileURLWithPath: projectPath),
            targetName: try parseFlag("--target", from: arguments)
        )
        print("Integrated ChromiumKit into \(result.projectURL.lastPathComponent) for target \(result.targetName)")
        print("Managed host support: \(result.supportPaths.directoryURL.path)")
        if result.removedLegacyRuntimePhase {
            print("Removed legacy inline CEF packaging from the Xcode project.")
        }
        if result.didMutateProject {
            print("Updated project build phases to use the managed ChromiumKit runtime step.")
        } else {
            print("Project already used the managed ChromiumKit runtime step.")
        }
    }

    private static func runRepair(arguments: [String]) throws {
        let projectPath = try parseRequiredFlag("--project", from: arguments)
        let result = try XcodeProjectIntegration.repair(
            projectURL: URL(fileURLWithPath: projectPath),
            targetName: try parseFlag("--target", from: arguments)
        )
        print("Repaired ChromiumKit integration for \(result.projectURL.lastPathComponent) target \(result.targetName)")
        print("Managed host support refreshed at \(result.supportPaths.directoryURL.path)")
    }

    private static func runNewHost(arguments: [String]) throws {
        let output = try parseFlag("--output", from: arguments) ?? "./ChromiumKitHostSupport"
        let outputURL = URL(fileURLWithPath: output)
        let paths = try HostSupportTemplate.install(at: outputURL)
        print("Generated ChromiumKit host support in \(paths.directoryURL.path)")
    }

    private static func runPrepareRelease(arguments: [String]) throws {
        let packageRoot = try parseFlag("--package-root", from: arguments) ?? FileManager.default.currentDirectoryPath
        let result = try ReleasePreparation.prepareRelease(
            packageRootURL: URL(fileURLWithPath: packageRoot),
            releaseURL: try parseFlag("--release-url", from: arguments)
        )
        print("Prepared ChromiumKit release artifact")
        print("Archive: \(result.archiveURL.path)")
        print("Checksum: \(result.checksum)")
        print("Metadata: \(result.metadataURL.path)")
    }

    private static func printDiagnostics(_ diagnostics: [ToolDiagnostic]) {
        diagnostics.forEach { diagnostic in
            let prefix = diagnostic.severity.rawValue.uppercased()
            if let path = diagnostic.path?.path {
                print("[\(prefix)] \(diagnostic.message) (\(path))")
            } else {
                print("[\(prefix)] \(diagnostic.message)")
            }
        }
    }

    private static func parseFlag(_ flag: String, from arguments: [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            throw ToolingError.message("Missing value for \(flag)")
        }

        return arguments[valueIndex]
    }

    private static func parseRequiredFlag(_ flag: String, from arguments: [String]) throws -> String {
        guard let value = try parseFlag(flag, from: arguments) else {
            throw ToolingError.message("Missing required flag \(flag)")
        }
        return value
    }

    private static func printUsage() {
        print(
            """
            Usage:
              chromiumkit doctor --project /path/to/MyApp.xcodeproj [--target MyApp]
              chromiumkit doctor /path/to/MyApp.app
              chromiumkit check-runtime /path/to/MyApp.app
              chromiumkit integrate --project /path/to/MyApp.xcodeproj [--target MyApp]
              chromiumkit repair --project /path/to/MyApp.xcodeproj [--target MyApp]
              chromiumkit new-host --output /path/to/ChromiumKitHostSupport
              chromiumkit prepare-release [--package-root /path/to/ChromiumKit] [--release-url https://github.com/org/repo/releases/download/tag/ChromiumEmbeddedFramework.xcframework.zip]
            """
        )
    }
}
