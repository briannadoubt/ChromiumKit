import Foundation

public enum ChromiumError: LocalizedError, Sendable {
    case runtimeConfiguration(String)
    case runtimeUnavailable(String)
    case navigationFailed(WebPage.NavigationFailure)
    case javaScriptEvaluation(String)
    case invalidDataLoad(String)

    public var errorDescription: String? {
        switch self {
        case let .runtimeConfiguration(message):
            return message
        case let .runtimeUnavailable(message):
            return message
        case let .navigationFailed(failure):
            return failure.description
        case let .javaScriptEvaluation(message):
            return message
        case let .invalidDataLoad(message):
            return message
        }
    }
}
