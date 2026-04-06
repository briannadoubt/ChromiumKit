import Foundation

public struct WebProfile: Sendable, Hashable {
    public enum Storage: Sendable, Hashable {
        case shared
        case ephemeral
        case persistent(URL)
    }

    public var storage: Storage

    public init(storage: Storage = .shared) {
        self.storage = storage
    }

    public static let `default` = WebProfile(storage: .shared)
    public static let ephemeral = WebProfile(storage: .ephemeral)

    static func defaultCacheRootDirectoryURL(bundle: Bundle = .main) -> URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?
            .appendingPathComponent(bundle.bundleIdentifier ?? "ChromiumKitHost", isDirectory: true)
            .appendingPathComponent("ChromiumKit", isDirectory: true)
    }

    func resolvedCacheDirectoryURL(cacheRootDirectoryURL: URL?) -> URL? {
        switch storage {
        case .ephemeral:
            return nil
        case .shared:
            return (cacheRootDirectoryURL ?? Self.defaultCacheRootDirectoryURL())?
                .appendingPathComponent("Profiles", isDirectory: true)
                .appendingPathComponent("Default", isDirectory: true)
        case let .persistent(url):
            return url
        }
    }
}
