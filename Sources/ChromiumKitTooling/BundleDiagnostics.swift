import Foundation

public enum BundleDiagnostics {
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
    ) -> [ToolDiagnostic] {
        let frameworksURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Frameworks", isDirectory: true)
        let frameworkURL = frameworksURL.appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)

        var diagnostics: [ToolDiagnostic] = []

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

    public static func inspectReleaseReadiness(
        appBundleURL: URL,
        helperAppName: String = "ChromiumKitHelper"
    ) -> [ToolDiagnostic] {
        let frameworksURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Frameworks", isDirectory: true)
        let frameworkURL = frameworksURL.appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)
        let helperURLs = helperNames(for: helperAppName).map {
            frameworksURL.appendingPathComponent("\($0).app", isDirectory: true)
        }

        var diagnostics = signingDiagnostics(for: appBundleURL, label: "App bundle")
        diagnostics.append(contentsOf: signingDiagnostics(for: frameworkURL, label: "CEF framework"))
        helperURLs.forEach { helperURL in
            diagnostics.append(contentsOf: signingDiagnostics(for: helperURL, label: helperURL.lastPathComponent))
        }
        return diagnostics
    }

    private static func signingDiagnostics(for bundleURL: URL, label: String) -> [ToolDiagnostic] {
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
        var diagnostics: [ToolDiagnostic] = [
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

    private static func runCodesignDisplay(on bundleURL: URL) -> ProcessResult {
        do {
            return try ToolingProcess.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["-dv", "--verbose=4", bundleURL.path]
            )
        } catch {
            return ProcessResult(standardOutput: "", standardError: error.localizedDescription, exitStatus: 1)
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
