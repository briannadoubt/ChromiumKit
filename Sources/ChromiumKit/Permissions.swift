import Foundation

public struct PermissionKind: OptionSet, Sendable, Hashable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let audioCapture = PermissionKind(rawValue: 1 << 0)
    public static let videoCapture = PermissionKind(rawValue: 1 << 1)
    public static let notifications = PermissionKind(rawValue: 1 << 2)
    public static let clipboard = PermissionKind(rawValue: 1 << 3)
}

public struct PermissionRequest: Sendable, Equatable {
    public var origin: URL?
    public var kinds: PermissionKind

    public init(origin: URL?, kinds: PermissionKind) {
        self.origin = origin
        self.kinds = kinds
    }
}

public enum PermissionDecision: Sendable, Equatable {
    case allow
    case deny
    case `default`
}

public protocol PermissionDeciding: AnyObject {
    func decidePermission(for request: PermissionRequest) -> PermissionDecision
}
