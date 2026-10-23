
@testable import SwiftSentry
import XCTest

final class UUIDTests: XCTestCase {
    func testUUIDHexadecimalEncoded() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "7B8EC5C3-8F1D-4F11-96BC-3C67A5D7F1DA"))
        XCTAssertEqual(uuid.hexadecimalEncoded, "7b8ec5c38f1d4f1196bc3c67a5d7f1da")

        let uuid2 = try XCTUnwrap(UUID(fromHexadecimalEncodedString: "7b8ec5c38f1d4f1196bc3c67a5d7f1da"))
        XCTAssertEqual(uuid, uuid2)

        let testEvent = try EventId(rawValue: XCTUnwrap(UUID(uuidString: "01234567-ABCD-AAAA-BBBB-ABCDEFABCDEF")))
        let json = try XCTUnwrap(try String(data: JSONEncoder().encode(testEvent), encoding: .utf8))

        XCTAssertEqual(json, "{\"event_id\":\"01234567abcdaaaabbbbabcdefabcdef\"}")

        let testEvent2 = try JSONDecoder().decode(EventId.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(testEvent.rawValue, testEvent2.rawValue)
    }
}
