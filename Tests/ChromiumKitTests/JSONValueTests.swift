import XCTest
@testable import ChromiumKit

final class JSONValueTests: XCTestCase {
    func testDecodesNestedJSON() throws {
        let data = Data(#"{"name":"lake","count":2,"items":[true,null]}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertEqual(
            value,
            .object([
                "name": .string("lake"),
                "count": .number(2),
                "items": .array([.bool(true), .null])
            ])
        )
    }
}
