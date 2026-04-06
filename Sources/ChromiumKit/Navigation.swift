import Foundation

public struct NavigationAction: Sendable, Equatable {
    public var url: URL
    public var isUserGesture: Bool
    public var isRedirect: Bool
    public var opensNewWindow: Bool

    public init(
        url: URL,
        isUserGesture: Bool,
        isRedirect: Bool,
        opensNewWindow: Bool
    ) {
        self.url = url
        self.isUserGesture = isUserGesture
        self.isRedirect = isRedirect
        self.opensNewWindow = opensNewWindow
    }
}

public enum NavigationDecision: Sendable, Equatable {
    case allow
    case cancel
    case openExternally
}

public protocol NavigationDeciding: AnyObject {
    func decidePolicy(for action: NavigationAction) -> NavigationDecision
}
