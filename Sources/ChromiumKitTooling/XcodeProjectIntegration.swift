import Foundation

public struct XcodeAppTarget: Sendable, Hashable {
    public var name: String
    public var productType: String?

    public init(name: String, productType: String?) {
        self.name = name
        self.productType = productType
    }
}

public struct IntegrationResult: Sendable, Hashable {
    public var projectURL: URL
    public var targetName: String
    public var supportPaths: HostSupportPaths
    public var didMutateProject: Bool
    public var removedLegacyRuntimePhase: Bool

    public init(
        projectURL: URL,
        targetName: String,
        supportPaths: HostSupportPaths,
        didMutateProject: Bool,
        removedLegacyRuntimePhase: Bool
    ) {
        self.projectURL = projectURL
        self.targetName = targetName
        self.supportPaths = supportPaths
        self.didMutateProject = didMutateProject
        self.removedLegacyRuntimePhase = removedLegacyRuntimePhase
    }
}

private struct PBXProjectDescription {
    struct Target: Sendable, Hashable {
        var identifier: String
        var name: String
        var productType: String?
    }

    var targets: [Target]
}

public enum XcodeProjectIntegration {
    public static func integrate(
        projectURL: URL,
        targetName: String? = nil,
        supportDirectoryName: String = HostSupportTemplate.defaultDirectoryName
    ) throws -> IntegrationResult {
        let resolvedProjectURL = try normalizeProjectURL(projectURL)
        let appTarget = try resolveAppTarget(in: resolvedProjectURL, requestedTargetName: targetName)
        let supportPaths = try HostSupportTemplate.install(
            into: resolvedProjectURL.deletingLastPathComponent(),
            directoryName: supportDirectoryName
        )

        let pbxprojURL = resolvedProjectURL
            .appendingPathComponent("project.pbxproj", isDirectory: false)
        let patchResult = try PBXProjPatcher.patch(
            pbxprojURL: pbxprojURL,
            targetName: appTarget.name,
            supportDirectoryName: supportDirectoryName
        )

        return IntegrationResult(
            projectURL: resolvedProjectURL,
            targetName: appTarget.name,
            supportPaths: supportPaths,
            didMutateProject: patchResult.didMutate,
            removedLegacyRuntimePhase: patchResult.removedLegacyRuntimePhase
        )
    }

    public static func repair(
        projectURL: URL,
        targetName: String? = nil,
        supportDirectoryName: String = HostSupportTemplate.defaultDirectoryName
    ) throws -> IntegrationResult {
        try integrate(projectURL: projectURL, targetName: targetName, supportDirectoryName: supportDirectoryName)
    }

    public static func inspectProject(
        projectURL: URL,
        targetName: String? = nil,
        supportDirectoryName: String = HostSupportTemplate.defaultDirectoryName
    ) throws -> [ToolDiagnostic] {
        let resolvedProjectURL = try normalizeProjectURL(projectURL)
        let appTarget = try resolveAppTarget(in: resolvedProjectURL, requestedTargetName: targetName)
        let pbxprojURL = resolvedProjectURL.appendingPathComponent("project.pbxproj", isDirectory: false)
        let projectDirectoryURL = resolvedProjectURL.deletingLastPathComponent()
        let supportDirectoryURL = projectDirectoryURL.appendingPathComponent(supportDirectoryName, isDirectory: true)
        let supportScriptURL = supportDirectoryURL.appendingPathComponent("embed_cef.sh", isDirectory: false)
        let helperAppURL = supportDirectoryURL.appendingPathComponent("ChromiumKitHelper.app", isDirectory: true)
        let helperExecutableURL = helperAppURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("ChromiumKitHelper", isDirectory: false)

        let manager = FileManager.default
        var diagnostics: [ToolDiagnostic] = []

        diagnostics.append(.init(severity: .info, message: "Resolved app target '\(appTarget.name)' for project integration.", path: resolvedProjectURL))

        if manager.fileExists(atPath: supportDirectoryURL.path) {
            diagnostics.append(.init(severity: .info, message: "Found managed ChromiumKit host support directory.", path: supportDirectoryURL))
        } else {
            diagnostics.append(.init(severity: .error, message: "Missing ChromiumKitHostSupport directory. Run 'Integrate ChromiumKit'.", path: supportDirectoryURL))
        }

        if manager.isExecutableFile(atPath: supportScriptURL.path) {
            diagnostics.append(.init(severity: .info, message: "Found managed embed_cef.sh script.", path: supportScriptURL))
        } else {
            diagnostics.append(.init(severity: .error, message: "Missing or non-executable embed_cef.sh in ChromiumKitHostSupport.", path: supportScriptURL))
        }

        if manager.fileExists(atPath: helperAppURL.path) {
            diagnostics.append(.init(severity: .info, message: "Found managed ChromiumKitHelper.app template.", path: helperAppURL))
        } else {
            diagnostics.append(.init(severity: .error, message: "Missing managed ChromiumKitHelper.app template. Re-run 'Repair ChromiumKit'.", path: helperAppURL))
        }

        if manager.isExecutableFile(atPath: helperExecutableURL.path) {
            diagnostics.append(.init(severity: .info, message: "Found managed ChromiumKit helper executable.", path: helperExecutableURL))
        } else {
            diagnostics.append(.init(severity: .error, message: "Missing or non-executable ChromiumKit helper binary in ChromiumKitHostSupport.", path: helperExecutableURL))
        }

        let pbxprojContents = try String(contentsOf: pbxprojURL, encoding: .utf8)
        if pbxprojContents.contains("ChromiumKit Managed Runtime"),
           pbxprojContents.contains("\(supportDirectoryName)/embed_cef.sh")
        {
            diagnostics.append(.init(severity: .info, message: "The app target uses the managed ChromiumKit build phase.", path: pbxprojURL))
        } else {
            diagnostics.append(.init(severity: .error, message: "The app target is missing the managed ChromiumKit build phase.", path: pbxprojURL))
        }

        if pbxprojContents.contains("Embed CEF Runtime") && !pbxprojContents.contains("\(supportDirectoryName)/embed_cef.sh") {
            diagnostics.append(.init(severity: .warning, message: "Legacy inline CEF packaging was detected. Run 'Repair ChromiumKit' to replace it with the managed build phase.", path: pbxprojURL))
        }

        return diagnostics
    }

    public static func availableAppTargets(in projectURL: URL) throws -> [XcodeAppTarget] {
        let resolvedProjectURL = try normalizeProjectURL(projectURL)
        return try loadProjectDescription(projectURL: resolvedProjectURL)
            .targets
            .filter { isApplicationType($0.productType) }
            .map { XcodeAppTarget(name: $0.name, productType: $0.productType) }
    }

    private static func normalizeProjectURL(_ projectURL: URL) throws -> URL {
        let normalizedURL: URL
        if projectURL.pathExtension == "xcodeproj" {
            normalizedURL = projectURL
        } else {
            normalizedURL = projectURL.appendingPathComponent("project.xcodeproj", isDirectory: true)
        }

        guard FileManager.default.fileExists(atPath: normalizedURL.path) else {
            throw ToolingError.message("Could not find an Xcode project at \(normalizedURL.path).")
        }

        return normalizedURL
    }

    private static func resolveAppTarget(in projectURL: URL, requestedTargetName: String?) throws -> XcodeAppTarget {
        let appTargets = try availableAppTargets(in: projectURL)

        if let requestedTargetName {
            guard let match = appTargets.first(where: { $0.name == requestedTargetName }) else {
                let availableTargets = appTargets.map(\.name).sorted().joined(separator: ", ")
                throw ToolingError.message("Could not find an application target named '\(requestedTargetName)' in \(projectURL.lastPathComponent). Available app targets: \(availableTargets)")
            }
            return match
        }

        guard let appTarget = appTargets.first else {
            throw ToolingError.message("No macOS application targets were found in \(projectURL.lastPathComponent).")
        }

        if appTargets.count > 1 {
            let names = appTargets.map(\.name).sorted().joined(separator: ", ")
            throw ToolingError.message("Multiple application targets were found in \(projectURL.lastPathComponent): \(names). Re-run with --target <name>.")
        }

        return appTarget
    }

    private static func loadProjectDescription(projectURL: URL) throws -> PBXProjectDescription {
        let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj", isDirectory: false)
        let contents = try String(contentsOf: pbxprojURL, encoding: .utf8)
        guard
            let sectionStart = contents.range(of: "/* Begin PBXNativeTarget section */")?.upperBound,
            let sectionEnd = contents.range(of: "/* End PBXNativeTarget section */")?.lowerBound
        else {
            throw ToolingError.message("Could not find the PBXNativeTarget section in \(pbxprojURL.path).")
        }

        let nativeTargetSection = String(contents[sectionStart..<sectionEnd])
        let blockStartPattern = #"(?m)^\s*([A-F0-9]{24}) /\* (.*?) \*/ = \{$"#
        let blockStartRegex = try NSRegularExpression(pattern: blockStartPattern)
        let range = NSRange(nativeTargetSection.startIndex..<nativeTargetSection.endIndex, in: nativeTargetSection)
        let productTypeRegex = try NSRegularExpression(pattern: #"(?m)^\s*productType = (?:"([^"]+)"|([^;]+));$"#)
        let targets = blockStartRegex.matches(in: nativeTargetSection, range: range).compactMap { match -> PBXProjectDescription.Target? in
            guard
                let identifierRange = Range(match.range(at: 1), in: nativeTargetSection),
                let nameRange = Range(match.range(at: 2), in: nativeTargetSection),
                let matchedRange = Range(match.range(at: 0), in: nativeTargetSection),
                let openingBrace = nativeTargetSection[matchedRange].lastIndex(of: "{")
            else {
                return nil
            }

            let blockStart = matchedRange.lowerBound
            let targetBlockRange: Range<String.Index>
            do {
                targetBlockRange = try nativeTargetBlockRange(
                    in: nativeTargetSection,
                    startingAt: openingBrace,
                    blockStart: blockStart
                )
            } catch {
                return nil
            }
            let blockContents = String(nativeTargetSection[targetBlockRange])
            guard blockContents.contains("isa = PBXNativeTarget;") else {
                return nil
            }

            let blockNSRange = NSRange(blockContents.startIndex..<blockContents.endIndex, in: blockContents)
            let productTypeMatch = productTypeRegex.firstMatch(in: blockContents, range: blockNSRange)
            let productType: String?
            if
                let productTypeMatch,
                let quotedProductTypeRange = Range(productTypeMatch.range(at: 1), in: blockContents)
            {
                productType = String(blockContents[quotedProductTypeRange])
            } else if
                let productTypeMatch,
                let unquotedProductTypeRange = Range(productTypeMatch.range(at: 2), in: blockContents)
            {
                productType = String(blockContents[unquotedProductTypeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                productType = nil
            }

            return PBXProjectDescription.Target(
                identifier: String(nativeTargetSection[identifierRange]),
                name: String(nativeTargetSection[nameRange]),
                productType: productType
            )
        }

        guard !targets.isEmpty else {
            throw ToolingError.message("Could not find any PBXNativeTarget definitions in \(pbxprojURL.path).")
        }

        return PBXProjectDescription(targets: targets)
    }

    private static func nativeTargetBlockRange(
        in contents: String,
        startingAt openingBrace: String.Index,
        blockStart: String.Index
    ) throws -> Range<String.Index> {
        var depth = 0
        var index = openingBrace
        while index < contents.endIndex {
            switch contents[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return blockStart..<contents.index(after: index)
                }
            default:
                break
            }
            index = contents.index(after: index)
        }

        throw ToolingError.message("Could not parse a PBXNativeTarget block.")
    }

    private static func isApplicationType(_ type: String?) -> Bool {
        guard let type else {
            return false
        }
        return type == "application" || type == "com.apple.product-type.application"
    }
}
