import Foundation

public struct ChromiumDiagnostic: Sendable, Hashable {
    public enum Severity: String, Sendable {
        case info
        case warning
        case error
    }

    public var severity: Severity
    public var message: String
    public var path: URL?

    public init(severity: Severity, message: String, path: URL? = nil) {
        self.severity = severity
        self.message = message
        self.path = path
    }
}

public enum ChromiumDiagnostics {
    private static func helperNames(for baseName: String) -> [String] {
        [
            baseName,
            "\(baseName) (Renderer)",
            "\(baseName) (GPU)",
            "\(baseName) (Plugin)",
            "\(baseName) (Alerts)"
        ]
    }

    public static func inspect(
        appBundleURL: URL,
        helperAppName: String = "ChromiumKitHelper"
    ) -> [ChromiumDiagnostic] {
        let frameworksURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Frameworks", isDirectory: true)
        let frameworkURL = frameworksURL.appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)

        var diagnostics: [ChromiumDiagnostic] = []

        if FileManager.default.fileExists(atPath: frameworkURL.path) {
            diagnostics.append(.init(severity: .info, message: "Found Chromium Embedded Framework.framework", path: frameworkURL))
        } else {
            diagnostics.append(.init(severity: .error, message: "Missing Chromium Embedded Framework.framework in the app bundle.", path: frameworkURL))
        }

        for helperName in helperNames(for: helperAppName) {
            let helperURL = frameworksURL.appendingPathComponent("\(helperName).app", isDirectory: true)
            let helperExecutableURL = helperURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent(helperName, isDirectory: false)

            if FileManager.default.fileExists(atPath: helperURL.path) {
                diagnostics.append(.init(severity: .info, message: "Found helper app bundle: \(helperName).app", path: helperURL))
            } else {
                diagnostics.append(.init(severity: .error, message: "Missing helper app bundle: \(helperName).app", path: helperURL))
            }

            if FileManager.default.isExecutableFile(atPath: helperExecutableURL.path) {
                diagnostics.append(.init(severity: .info, message: "Found helper executable: \(helperName)", path: helperExecutableURL))
            } else {
                diagnostics.append(.init(severity: .error, message: "Missing helper executable: \(helperName)", path: helperExecutableURL))
            }
        }

        return diagnostics
    }

    public static func inspectProject(
        projectURL: URL,
        supportDirectoryName: String = "ChromiumKitHostSupport"
    ) -> [ChromiumDiagnostic] {
        let resolvedProjectURL: URL
        if projectURL.pathExtension == "xcodeproj" {
            resolvedProjectURL = projectURL
        } else {
            resolvedProjectURL = projectURL.appendingPathComponent("project.xcodeproj", isDirectory: true)
        }

        let pbxprojURL = resolvedProjectURL.appendingPathComponent("project.pbxproj", isDirectory: false)
        let supportDirectoryURL = resolvedProjectURL
            .deletingLastPathComponent()
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
        let supportScriptURL = supportDirectoryURL.appendingPathComponent("embed_cef.sh", isDirectory: false)
        let helperExecutableURL = supportDirectoryURL
            .appendingPathComponent("ChromiumKitHelper.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("ChromiumKitHelper", isDirectory: false)

        var diagnostics: [ChromiumDiagnostic] = []

        diagnostics.append(
            FileManager.default.fileExists(atPath: resolvedProjectURL.path)
                ? .init(severity: .info, message: "Found Xcode project.", path: resolvedProjectURL)
                : .init(severity: .error, message: "Missing Xcode project.", path: resolvedProjectURL)
        )
        diagnostics.append(
            FileManager.default.fileExists(atPath: supportDirectoryURL.path)
                ? .init(severity: .info, message: "Found managed ChromiumKitHostSupport directory.", path: supportDirectoryURL)
                : .init(severity: .error, message: "Missing ChromiumKitHostSupport directory.", path: supportDirectoryURL)
        )
        diagnostics.append(
            FileManager.default.isExecutableFile(atPath: supportScriptURL.path)
                ? .init(severity: .info, message: "Found executable embed_cef.sh.", path: supportScriptURL)
                : .init(severity: .error, message: "Missing or non-executable embed_cef.sh in ChromiumKitHostSupport.", path: supportScriptURL)
        )
        diagnostics.append(
            FileManager.default.isExecutableFile(atPath: helperExecutableURL.path)
                ? .init(severity: .info, message: "Found managed ChromiumKit helper executable.", path: helperExecutableURL)
                : .init(severity: .error, message: "Missing or non-executable ChromiumKit helper executable in ChromiumKitHostSupport.", path: helperExecutableURL)
        )

        if
            let contents = try? String(contentsOf: pbxprojURL, encoding: .utf8),
            contents.contains("ChromiumKit Managed Runtime"),
            contents.contains("\(supportDirectoryName)/embed_cef.sh")
        {
            diagnostics.append(.init(severity: .info, message: "Found the managed ChromiumKit build phase in the Xcode project.", path: pbxprojURL))
        } else {
            diagnostics.append(.init(severity: .error, message: "The Xcode project is missing the managed ChromiumKit build phase.", path: pbxprojURL))
        }

        return diagnostics
    }

    public static func inspectReleaseReadiness(
        appBundleURL: URL,
        helperAppName: String = "ChromiumKitHelper"
    ) -> [ChromiumDiagnostic] {
        let frameworksURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Frameworks", isDirectory: true)
        let frameworkURL = frameworksURL.appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)
        let helperURLs = helperNames(for: helperAppName).map {
            frameworksURL.appendingPathComponent("\($0).app", isDirectory: true)
        }

        var diagnostics: [ChromiumDiagnostic] = signingDiagnostics(for: appBundleURL, label: "App bundle")
        diagnostics.append(contentsOf: signingDiagnostics(for: frameworkURL, label: "CEF framework"))
        helperURLs.forEach { helperURL in
            diagnostics.append(contentsOf: signingDiagnostics(for: helperURL, label: helperURL.lastPathComponent))
        }
        return diagnostics
    }

    private static func signingDiagnostics(for bundleURL: URL, label: String) -> [ChromiumDiagnostic] {
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            return [.init(severity: .error, message: "\(label) is missing from the bundle layout.", path: bundleURL)]
        }

        let result = runCodesignDisplay(on: bundleURL)
        guard result.exitStatus == 0 else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return [.init(severity: .warning, message: "\(label) is not code signed: \(message)", path: bundleURL)]
        }

        let stderr = result.standardError
        let teamIdentifier = captureField("TeamIdentifier", in: stderr)
        let runtimeVersion = captureField("Runtime Version", in: stderr)
        var diagnostics: [ChromiumDiagnostic] = [
            .init(severity: .info, message: "\(label) is code signed.", path: bundleURL)
        ]

        if let teamIdentifier, !teamIdentifier.isEmpty {
            diagnostics.append(.init(severity: .info, message: "\(label) uses team identifier \(teamIdentifier).", path: bundleURL))
        } else {
            diagnostics.append(.init(severity: .warning, message: "\(label) does not report a team identifier. Ad-hoc signing is fine for local development but not for release.", path: bundleURL))
        }

        if runtimeVersion == nil, bundleURL.pathExtension == "app" {
            diagnostics.append(.init(severity: .warning, message: "\(label) does not report a hardened runtime. Verify release signing settings before distribution.", path: bundleURL))
        }

        return diagnostics
    }

    private static func runCodesignDisplay(on bundleURL: URL) -> (standardError: String, exitStatus: Int32) {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", bundleURL.path]
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            return (String(decoding: data, as: UTF8.self), process.terminationStatus)
        } catch {
            return (error.localizedDescription, 1)
        }
    }

    private static func captureField(_ name: String, in output: String) -> String? {
        output
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("\(name)=") else {
                    return nil
                }
                return String(line.dropFirst(name.count + 1))
            }
            .first
    }
}
