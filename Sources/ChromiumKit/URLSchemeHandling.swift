import Foundation

public struct URLSchemeResponse: Sendable, Equatable {
    public var data: Data
    public var mimeType: String
    public var statusCode: Int
    public var headers: [String: String]

    public init(
        data: Data,
        mimeType: String = "text/html",
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) {
        self.data = data
        self.mimeType = mimeType
        self.statusCode = statusCode
        self.headers = headers
    }
}

public protocol URLSchemeHandling: AnyObject {
    func response(for request: URLRequest) throws -> URLSchemeResponse
}
