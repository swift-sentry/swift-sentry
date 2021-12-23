
import XCTest
@testable import SwiftSentry

final class UUIDTests: XCTestCase {
    func testUUIDHexadecimalEncoded() throws {
        struct TestEvent: Codable {
            @UUIDHexadecimalEncoded
            var event_id: UUID
        }

        let uuid = UUID(uuidString: "7B8EC5C3-8F1D-4F11-96BC-3C67A5D7F1DA")!
        XCTAssertEqual(uuid.hexadecimalEncoded, "7b8ec5c38f1d4f1196bc3c67a5d7f1da")

        let uuid2 = UUID(fromHexadecimalEncodedString: "7b8ec5c38f1d4f1196bc3c67a5d7f1da")!
        XCTAssertEqual(uuid, uuid2)

        let testEvent = TestEvent(event_id: UUID(uuidString: "01234567-ABCD-AAAA-BBBB-ABCDEFABCDEF")!)
        let json = String(data: try JSONEncoder().encode(testEvent), encoding: .utf8)!

        XCTAssertEqual(json, "{\"event_id\":\"01234567abcdaaaabbbbabcdefabcdef\"}")

        let testEvent2 = try JSONDecoder().decode(TestEvent.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(testEvent.event_id, testEvent2.event_id)
    }
}
