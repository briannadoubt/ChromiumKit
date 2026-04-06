import ChromiumKitBridge
import Foundation

@MainActor
public enum ChromiumRuntime {
    public struct Configuration: Sendable {
        public var cacheDirectoryURL: URL?
        public var logDirectoryURL: URL?
        public var helperExecutableURL: URL?
        public var additionalArguments: [String]

        public init(
            cacheDirectoryURL: URL? = nil,
            logDirectoryURL: URL? = nil,
            helperExecutableURL: URL? = nil,
            additionalArguments: [String] = []
        ) {
            self.cacheDirectoryURL = cacheDirectoryURL
            self.logDirectoryURL = logDirectoryURL
            self.helperExecutableURL = helperExecutableURL
            self.additionalArguments = additionalArguments
        }
    }

    private static var configuration = Configuration()
    private static var lockedSchemes = Set<String>()
    private static var initialized = false

    public static func configure(_ update: (inout Configuration) -> Void) throws {
        guard !initialized else {
            throw ChromiumError.runtimeConfiguration("ChromiumRuntime.configure must be called before the first WebPage or WebView is created.")
        }
        update(&configuration)
    }

    public static func prewarm(knownCustomSchemes: some Sequence<String> = []) throws {
        try registerKnownSchemes(knownCustomSchemes)
        try ensureInitialized()
    }

    public static func shutdown() {
        CKRuntime.shutdown()
        initialized = false
    }

    public static func diagnostics(
        appBundleURL: URL = Bundle.main.bundleURL,
        helperAppName: String = "ChromiumKitHelper"
    ) -> [ChromiumDiagnostic] {
        ChromiumDiagnostics.inspect(appBundleURL: appBundleURL, helperAppName: helperAppName)
    }

    static func registerKnownSchemes(_ schemes: some Sequence<String>) throws {
        let normalized = Set(schemes.map { $0.lowercased() }.filter { !$0.isEmpty })
        let newSchemes = normalized.subtracting(lockedSchemes)
        guard !initialized || newSchemes.isEmpty else {
            let names = newSchemes.sorted().joined(separator: ", ")
            throw ChromiumError.runtimeConfiguration("Custom schemes must be registered before Chromium initializes. Late schemes: \(names)")
        }
        lockedSchemes.formUnion(normalized)
    }

    static func ensureInitialized() throws {
        guard !initialized else {
            return
        }

        let runtimeConfiguration = CKRuntimeConfiguration()
        runtimeConfiguration.cacheDirectoryURL = resolvedCacheRootDirectoryURL()
        runtimeConfiguration.logDirectoryURL = configuration.logDirectoryURL
        runtimeConfiguration.helperExecutableURL = configuration.helperExecutableURL ?? defaultHelperExecutableURL()
        runtimeConfiguration.additionalArguments = configuration.additionalArguments
        runtimeConfiguration.knownCustomSchemes = lockedSchemes.sorted()

        try CKRuntime.ensureInitialized(with: runtimeConfiguration)

        initialized = true
    }

    private static func defaultHelperExecutableURL() -> URL? {
        Bundle.main.privateFrameworksURL?
            .appendingPathComponent("ChromiumKitHelper.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("ChromiumKitHelper", isDirectory: false)
    }

    static func resolvedCacheRootDirectoryURL() -> URL? {
        configuration.cacheDirectoryURL ?? WebProfile.defaultCacheRootDirectoryURL()
    }

    static func resolvedCacheDirectoryURL(for profile: WebProfile) -> URL? {
        profile.resolvedCacheDirectoryURL(cacheRootDirectoryURL: resolvedCacheRootDirectoryURL())
    }
}
