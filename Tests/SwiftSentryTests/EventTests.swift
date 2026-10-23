import Foundation
import Logging
@testable import SwiftSentry
import Testing

struct EventTests {
    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try #require(String(data: encoder.encode(value), encoding: .utf8))
    }

    @Test(arguments: [
        (Logger.Level.trace, Level.debug),
        (.debug, .debug),
        (.info, .info),
        (.notice, .info),
        (.warning, .warning),
        (.error, .error),
        (.critical, .fatal),
    ])
    func `level from logger level`(_ loggerLevel: Logger.Level, _ expected: Level) {
        #expect(Level(from: loggerLevel) == expected)
    }

    @Test
    func `raw message encodes as string`() throws {
        #expect(try json(Message.raw(message: "hello")) == "\"hello\"")
    }

    @Test
    func `format message encodes as object`() throws {
        #expect(
            try json(Message.format(message: "hello %s", params: ["world"]))
                == #"{"message":"hello %s","params":["world"]}"#
        )
    }

    @Test(arguments: [
        #""zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz""#, // non-hexadecimal
        #""abc""#, // too short
    ])
    func `event id rejects invalid string`(_ json: String) {
        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(EventId.self, from: Data(json.utf8))
        }
        guard case .typeMismatch? = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }

    @Test
    func `event encoding omits nil fields`() throws {
        let uuid = try #require(UUID(uuidString: "01234567-ABCD-AAAA-BBBB-ABCDEFABCDEF"))
        let event = Event(event_id: uuid, timestamp: 1_700_000_000, level: .error, message: .raw(message: "boom"))
        #expect(
            try json(event)
                == #"{"event_id":"01234567abcdaaaabbbbabcdefabcdef","level":"error","message":"boom","platform":"other","timestamp":1700000000}"#
        )
    }

    @Test
    func `event encoding with nested types`() throws {
        let uuid = try #require(UUID(uuidString: "01234567-ABCD-AAAA-BBBB-ABCDEFABCDEF"))
        let event = Event(
            event_id: uuid,
            timestamp: 1,
            tags: ["a": "b"],
            exception: Exceptions(values: [
                ExceptionDataBag(type: "T", value: "V", stacktrace: Stacktrace(frames: [Frame(filename: "f.swift", lineno: 3)])),
            ]),
            breadcrumbs: Breadcrumbs(values: [Breadcrumb(message: "crumb", level: .info, timestamp: 2)]),
            user: User(id: "u1", ip_address: "127.0.0.1")
        )
        let decoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        #expect(decoded["tags"] as? [String: String] == ["a": "b"])

        let exceptions = try #require((decoded["exception"] as? [String: Any])?["values"] as? [[String: Any]])
        try #require(exceptions.count == 1)
        #expect(exceptions[0]["type"] as? String == "T")
        #expect(exceptions[0]["value"] as? String == "V")
        let frames = try #require((exceptions[0]["stacktrace"] as? [String: Any])?["frames"] as? [[String: Any]])
        #expect(frames.first?["filename"] as? String == "f.swift")
        #expect(frames.first?["lineno"] as? Int == 3)

        let crumbs = try #require((decoded["breadcrumbs"] as? [String: Any])?["values"] as? [[String: Any]])
        #expect(crumbs.first?["message"] as? String == "crumb")
        #expect(crumbs.first?["level"] as? String == "info")

        let user = try #require(decoded["user"] as? [String: String])
        #expect(user == ["id": "u1", "ip_address": "127.0.0.1"])
    }
}
