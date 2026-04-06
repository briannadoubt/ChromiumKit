import Foundation

struct PBXProjPatchResult {
    var didMutate = false
    var removedLegacyRuntimePhase = false
    var installedManagedRuntimePhase = false
}

enum PBXProjPatcher {
    private static let managedPhaseComment = "ChromiumKit Managed Runtime"

    static func patch(
        pbxprojURL: URL,
        targetName: String,
        supportDirectoryName: String = HostSupportTemplate.defaultDirectoryName
    ) throws -> PBXProjPatchResult {
        var contents = try String(contentsOf: pbxprojURL, encoding: .utf8)
        let originalContents = contents
        var result = PBXProjPatchResult()

        let targetIdentifier = try findTargetIdentifier(named: targetName, in: contents)

        let existingManagedPhaseIdentifier = findManagedRuntimePhaseIdentifier(in: contents)
        let legacyPhaseIdentifiers = findLegacyRuntimePhaseIdentifiers(in: contents)

        for legacyIdentifier in legacyPhaseIdentifiers {
            contents = removeShellScriptBuildPhase(identifier: legacyIdentifier, from: contents)
            let currentTargetBlockRange = try findTargetBlock(identifier: targetIdentifier, in: contents)
            contents = removeBuildPhaseReference(
                identifier: legacyIdentifier,
                targetBlockRange: currentTargetBlockRange,
                from: contents
            )
            result.removedLegacyRuntimePhase = true
        }

        let phaseIdentifier: String
        if let existingManagedPhaseIdentifier {
            phaseIdentifier = existingManagedPhaseIdentifier
            contents = updateManagedShellScriptBuildPhase(
                identifier: phaseIdentifier,
                supportDirectoryName: supportDirectoryName,
                in: contents
            )
        } else {
            phaseIdentifier = makeIdentifier(seed: targetIdentifier + managedPhaseComment)
            contents = insertManagedShellScriptBuildPhase(
                identifier: phaseIdentifier,
                supportDirectoryName: supportDirectoryName,
                into: contents
            )
            result.installedManagedRuntimePhase = true
        }

        let refreshedTargetBlockRange = try findTargetBlock(identifier: targetIdentifier, in: contents)
        let targetBlock = String(contents[refreshedTargetBlockRange])
        if !targetBlock.contains("\(phaseIdentifier) /* \(managedPhaseComment) */") {
            contents = insertBuildPhaseReference(
                identifier: phaseIdentifier,
                targetBlockRange: refreshedTargetBlockRange,
                in: contents
            )
            result.installedManagedRuntimePhase = true
        }

        if contents != originalContents {
            try contents.write(to: pbxprojURL, atomically: true, encoding: .utf8)
            result.didMutate = true
        }

        return result
    }

    private static func findTargetIdentifier(named targetName: String, in contents: String) throws -> String {
        let escapedTargetName = NSRegularExpression.escapedPattern(for: targetName)
        let pattern = #"(?m)^\s*([A-F0-9]{24}) /\* \#(escapedTargetName) \*/ = \{\s*$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        guard
            let match = regex.firstMatch(in: contents, range: range),
            let identifierRange = Range(match.range(at: 1), in: contents)
        else {
            throw ToolingError.message("Could not find an app target named '\(targetName)' in project.pbxproj.")
        }
        return String(contents[identifierRange])
    }

    private static func findTargetBlock(identifier: String, in contents: String) throws -> Range<String.Index> {
        do {
            return try findObjectBlock(identifier: identifier, in: contents)
        } catch {
            throw ToolingError.message("Could not parse the PBXNativeTarget block for target identifier \(identifier).")
        }
    }

    private static func findManagedRuntimePhaseIdentifier(in contents: String) -> String? {
        let pattern = #"(?m)^\s*([A-F0-9]{24}) /\* ChromiumKit Managed Runtime \*/ = \{\s*$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: contents, range: NSRange(contents.startIndex..<contents.endIndex, in: contents)),
            let identifierRange = Range(match.range(at: 1), in: contents)
        else {
            return nil
        }
        return String(contents[identifierRange])
    }

    private static func findLegacyRuntimePhaseIdentifiers(in contents: String) -> [String] {
        let pattern = #"(?s)([A-F0-9]{24}) /\* ([^*]+) \*/ = \{\s*isa = PBXShellScriptBuildPhase;.*?shellScript = "(.*?)";\s*\};"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return regex.matches(in: contents, range: range).compactMap { match in
            guard
                let identifierRange = Range(match.range(at: 1), in: contents),
                let scriptRange = Range(match.range(at: 3), in: contents)
            else {
                return nil
            }

            let script = String(contents[scriptRange])
            guard script.contains("Chromium Embedded Framework"),
                  script.contains("ChromiumKitHelper"),
                  !script.contains("ChromiumKitHostSupport")
            else {
                return nil
            }

            return String(contents[identifierRange])
        }
    }

    private static func removeShellScriptBuildPhase(identifier: String, from contents: String) -> String {
        guard let blockRange = try? findObjectBlock(identifier: identifier, in: contents) else {
            return contents
        }

        var removalEnd = blockRange.upperBound
        if removalEnd < contents.endIndex, contents[removalEnd] == ";" {
            removalEnd = contents.index(after: removalEnd)
        }
        if removalEnd < contents.endIndex, contents[removalEnd] == "\n" {
            removalEnd = contents.index(after: removalEnd)
        }

        var updatedContents = contents
        updatedContents.removeSubrange(blockRange.lowerBound..<removalEnd)
        return updatedContents
    }

    private static func removeBuildPhaseReference(
        identifier: String,
        targetBlockRange: Range<String.Index>,
        from contents: String
    ) -> String {
        let pattern = #"(?m)^\s*\#(identifier) /\* .*? \*/,\n"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return contents
        }

        let targetBlock = String(contents[targetBlockRange])
        let range = NSRange(targetBlock.startIndex..<targetBlock.endIndex, in: targetBlock)
        let updatedTargetBlock = regex.stringByReplacingMatches(in: targetBlock, range: range, withTemplate: "")

        var updatedContents = contents
        updatedContents.replaceSubrange(targetBlockRange, with: updatedTargetBlock)
        return updatedContents
    }

    private static func updateManagedShellScriptBuildPhase(
        identifier: String,
        supportDirectoryName: String,
        in contents: String
    ) -> String {
        guard let blockRange = try? findObjectBlock(identifier: identifier, in: contents) else {
            return contents
        }

        var block = String(contents[blockRange])
        guard
            let shellScriptLineRange = block.range(
                of: #"(?m)^\s*shellScript = .*?;\s*$"#,
                options: .regularExpression
            )
        else {
            return contents
        }

        let replacementLine = "\t\t\tshellScript = \(managedScriptPath(for: supportDirectoryName));"
        block.replaceSubrange(shellScriptLineRange, with: replacementLine)

        if
            let outputPathsRange = block.range(
                of: #"(?s)\t\t\toutputPaths = \(\n.*?\t\t\t\);\n"#,
                options: .regularExpression
            )
        {
            block.replaceSubrange(outputPathsRange, with: managedOutputPathsBlock())
        }

        var updated = contents
        updated.replaceSubrange(blockRange, with: block)
        return updated
    }

    private static func insertManagedShellScriptBuildPhase(
        identifier: String,
        supportDirectoryName: String,
        into contents: String
    ) -> String {
        let phaseObject =
            """
\t\t\(identifier) /* \(managedPhaseComment) */ = {
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputFileListPaths = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t\t"$(PROJECT_DIR)/\(supportDirectoryName)/embed_cef.sh",
\t\t\t\t"$(PROJECT_DIR)/\(supportDirectoryName)/ChromiumKitHelper.app",
\t\t\t);
\t\t\tname = "\(managedPhaseComment)";
\t\t\toutputFileListPaths = (
\t\t\t);
\(managedOutputPathsBlock())\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = \(managedScriptPath(for: supportDirectoryName));
\t\t\tshowEnvVarsInLog = 0;
\t\t};
"""

        let marker = "/* End PBXShellScriptBuildPhase section */"
        if let markerRange = contents.range(of: marker) {
            var updated = contents
            updated.insert(contentsOf: phaseObject + "\n", at: markerRange.lowerBound)
            return updated
        }

        let section =
            """
/* Begin PBXShellScriptBuildPhase section */
\(phaseObject)/* End PBXShellScriptBuildPhase section */

"""

        let fallbackMarker = "/* Begin PBXNativeTarget section */"
        guard let fallbackMarkerRange = contents.range(of: fallbackMarker) else {
            return contents
        }

        var updated = contents
        updated.insert(contentsOf: section, at: fallbackMarkerRange.lowerBound)
        return updated
    }

    private static func insertBuildPhaseReference(
        identifier: String,
        targetBlockRange: Range<String.Index>,
        in contents: String
    ) -> String {
        let targetBlock = String(contents[targetBlockRange])
        guard let buildPhasesRange = targetBlock.range(of: "buildPhases = (\n") else {
            return contents
        }

        let insertionPoint = targetBlock[buildPhasesRange.upperBound...].range(of: "\t\t\t);")?.lowerBound ?? targetBlock.endIndex
        var updatedTargetBlock = targetBlock
        updatedTargetBlock.insert(contentsOf: "\t\t\t\t\(identifier) /* \(managedPhaseComment) */,\n", at: insertionPoint)

        var updatedContents = contents
        updatedContents.replaceSubrange(targetBlockRange, with: updatedTargetBlock)
        return updatedContents
    }

    private static func managedScriptPath(for supportDirectoryName: String) -> String {
        "\"\\\"$PROJECT_DIR/\(supportDirectoryName)/embed_cef.sh\\\"\\n\""
    }

    private static func managedOutputPathsBlock() -> String {
        """
\t\t\toutputPaths = (
\t\t\t\t"$(TARGET_BUILD_DIR)/$(FULL_PRODUCT_NAME)/Contents/Frameworks/ChromiumKitHelper.app",
\t\t\t);
"""
    }

    private static func findObjectBlock(identifier: String, in contents: String) throws -> Range<String.Index> {
        guard
            let definitionRegex = try? NSRegularExpression(
                pattern: #"(?m)^\s*\#(identifier) /\* .*? \*/ = \{\s*$"#
            ),
            let match = definitionRegex.firstMatch(
                in: contents,
                range: NSRange(contents.startIndex..<contents.endIndex, in: contents)
            ),
            let matchedRange = Range(match.range(at: 0), in: contents),
            let openingBrace = contents[matchedRange].lastIndex(of: "{")
        else {
            throw ToolingError.message("Could not find the project object block for identifier \(identifier).")
        }

        let start = matchedRange.lowerBound
        var depth = 0
        var index = openingBrace
        while index < contents.endIndex {
            switch contents[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return start..<contents.index(after: index)
                }
            default:
                break
            }

            index = contents.index(after: index)
        }

        throw ToolingError.message("Could not parse the project object block for identifier \(identifier).")
    }

    private static func makeIdentifier(seed: String) -> String {
        let digest = seed
            .unicodeScalars
            .map { String(format: "%02X", $0.value & 0xFF) }
            .joined()
        if digest.count >= 24 {
            return String(digest.prefix(24))
        }
        return digest.padding(toLength: 24, withPad: "0", startingAt: 0)
    }
}
