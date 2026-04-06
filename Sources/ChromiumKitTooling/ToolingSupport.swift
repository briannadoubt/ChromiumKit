import Foundation

public enum ToolingError: LocalizedError {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}

public struct ToolDiagnostic: Sendable, Hashable {
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

struct ProcessResult {
    var standardOutput: String
    var standardError: String
    var exitStatus: Int32
}

enum ToolingProcess {
    @discardableResult
    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String] = [:]
    ) throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        if !environment.isEmpty {
            var mergedEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                mergedEnvironment[key] = value
            }
            process.environment = mergedEnvironment
        }
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let stdoutData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let stderrData = standardError.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: String(decoding: stderrData, as: UTF8.self),
            exitStatus: process.terminationStatus
        )
    }
}

enum FileSystemSupport {
    static func ensureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func replaceDirectory(at destinationURL: URL, with sourceURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    static func copyItemReplacingExisting(from sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    static func makeExecutable(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
