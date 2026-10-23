import Foundation
@testable import SwiftSentry
import Testing

struct UUIDTests {
    @Test func uuidHexadecimalEncoded() throws {
        struct TestEvent: Codable {
            var event_id: EventId
        }

        let uuid = try #require(UUID(uuidString: "7B8EC5C3-8F1D-4F11-96BC-3C67A5D7F1DA"))
        #expect(uuid.hexadecimalEncoded == "7b8ec5c38f1d4f1196bc3c67a5d7f1da")

        let uuid2 = try #require(UUID(fromHexadecimalEncodedString: "7b8ec5c38f1d4f1196bc3c67a5d7f1da"))
        #expect(uuid == uuid2)

        let testEvent = try TestEvent(event_id: EventId(rawValue: #require(UUID(uuidString: "01234567-ABCD-AAAA-BBBB-ABCDEFABCDEF"))))
        let json = try #require(try String(data: JSONEncoder().encode(testEvent), encoding: .utf8))

        #expect(json == "{\"event_id\":\"01234567abcdaaaabbbbabcdefabcdef\"}")

        let testEvent2 = try JSONDecoder().decode(TestEvent.self, from: Data(json.utf8))

        #expect(testEvent.event_id == testEvent2.event_id)
    }

    @Test(arguments: [
        "",
        "abc",
        "7b8ec5c38f1d4f1196bc3c67a5d7f1d",
        "7b8ec5c38f1d4f1196bc3c67a5d7f1daa",
    ])
    func hexadecimalEncodedStringWithWrongLengthIsRejected(_ value: String) {
        #expect(UUID(fromHexadecimalEncodedString: value) == nil)
    }
}
