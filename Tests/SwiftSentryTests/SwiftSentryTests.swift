import XCTest
@testable import SwiftSentry

final class SwiftSentryTests: XCTestCase {
    func testParseEmptyStacktrace() throws {
        let dummyStacktrace1 = ""
        let dummyStacktrace2 = " "
        let dummyStacktrace3 = " \n "
        let dummyStacktrace4 = ""
        let dummyStacktrace5 = "\t"
        let dummyStacktrace6 = "\t\r\n\t"
        let dummyStacktrace7 = """
        \t
           
        \r
        
         \t  \t
        """

        XCTAssertEqual(Sentry.parseStacktrace(lines: dummyStacktrace1.split(separator: "\n")).count, 0)
        XCTAssertEqual(Sentry.parseStacktrace(lines: dummyStacktrace2.split(separator: "\n")).count, 0)
        XCTAssertEqual(Sentry.parseStacktrace(lines: dummyStacktrace3.split(separator: "\n")).count, 0)
        XCTAssertEqual(Sentry.parseStacktrace(lines: dummyStacktrace4.split(separator: "\n")).count, 0)
        XCTAssertEqual(Sentry.parseStacktrace(lines: dummyStacktrace5.split(separator: "\n")).count, 0)
        XCTAssertEqual(Sentry.parseStacktrace(lines: dummyStacktrace6.split(separator: "\n")).count, 0)
        XCTAssertEqual(Sentry.parseStacktrace(lines: dummyStacktrace7.split(separator: "\n")).count, 0)
    }

    func testParseStacktraceOnlyHeader() throws {
        let dummyStacktrace1 = "fatalError"
        let dummyStacktrace2 = "fatalError\nSomething happend"
        let dummyStacktrace3 = "fatalError\t\nSomething happend\t\n\t"

        let stacktrace1 = Sentry.parseStacktrace(lines: dummyStacktrace1.split(separator: "\n"))
        let stacktrace2 = Sentry.parseStacktrace(lines: dummyStacktrace2.split(separator: "\n"))
        let stacktrace3 = Sentry.parseStacktrace(lines: dummyStacktrace3.split(separator: "\n"))

        XCTAssertEqual(stacktrace1.count, 1)
        XCTAssertEqual(stacktrace2.count, 1)
        XCTAssertEqual(stacktrace3.count, 1)

        XCTAssertEqual(stacktrace1[0].msg, "fatalError")
        XCTAssertEqual(stacktrace2[0].msg, "fatalError\nSomething happend")
        XCTAssertEqual(stacktrace3[0].msg, "fatalError\nSomething happend")

        XCTAssertEqual(stacktrace1[0].stacktrace, Stacktrace(frames: []))
        XCTAssertEqual(stacktrace2[0].stacktrace, Stacktrace(frames: []))
        XCTAssertEqual(stacktrace3[0].stacktrace, Stacktrace(frames: []))
    }

    func testParseStacktrace() throws {
        let dummyStacktrace = """
        0x3141
        0xe893
        0x0350, func22 at /some/path.swift:3
        0x0000
        """

        let a = Sentry.parseStacktrace(lines: dummyStacktrace.split(separator: "\n"))
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].msg, "")
        XCTAssertEqual(a[0].stacktrace.frames.count, 4)
        XCTAssertEqual(a[0].stacktrace.frames[3], Frame(filename: nil, function: nil, raw_function: nil, lineno: nil, colno: nil, abs_path: nil, instruction_addr: "0x3141"))
        XCTAssertEqual(a[0].stacktrace.frames[2], Frame(filename: nil, function: nil, raw_function: nil, lineno: nil, colno: nil, abs_path: nil, instruction_addr: "0xe893"))
        XCTAssertEqual(a[0].stacktrace.frames[1], Frame(filename: nil, function: "func22", raw_function: nil, lineno: 3, colno: nil, abs_path: "/some/path.swift", instruction_addr: "0x0350"))
        XCTAssertEqual(a[0].stacktrace.frames[0], Frame(filename: nil, function: nil, raw_function: nil, lineno: nil, colno: nil, abs_path: nil, instruction_addr: "0x0000"))
    }

    func testParseStacktraceComplete() throws {
        let dummyStacktrace = """
        fatalError 1
        Something happend
        0x3141
        0xe893
        0x0350, func22 at /some/path.swift:3
        0x0000
        fatalError 2
        Something else happend
        0x3142, func12 at /some/path1.swift:1
        0xe894, func22 at /some/path2.swift:2
        0x0350, func32 at /some/path3.swift:3
        """

        let a = Sentry.parseStacktrace(lines: dummyStacktrace.split(separator: "\n"))
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a[0].msg, "fatalError 1\nSomething happend")
        XCTAssertEqual(a[0].stacktrace.frames.count, 4)
        XCTAssertEqual(a[0].stacktrace.frames[3], Frame(filename: nil, function: nil, raw_function: nil, lineno: nil, colno: nil, abs_path: nil, instruction_addr: "0x3141"))
        XCTAssertEqual(a[0].stacktrace.frames[2], Frame(filename: nil, function: nil, raw_function: nil, lineno: nil, colno: nil, abs_path: nil, instruction_addr: "0xe893"))
        XCTAssertEqual(a[0].stacktrace.frames[1], Frame(filename: nil, function: "func22", raw_function: nil, lineno: 3, colno: nil, abs_path: "/some/path.swift", instruction_addr: "0x0350"))
        XCTAssertEqual(a[0].stacktrace.frames[0], Frame(filename: nil, function: nil, raw_function: nil, lineno: nil, colno: nil, abs_path: nil, instruction_addr: "0x0000"))

        XCTAssertEqual(a[1].msg, "fatalError 2\nSomething else happend")
        XCTAssertEqual(a[1].stacktrace.frames.count, 3)
        XCTAssertEqual(a[1].stacktrace.frames[2], Frame(filename: nil, function: "func12", raw_function: nil, lineno: 1, colno: nil, abs_path: "/some/path1.swift", instruction_addr: "0x3142"))
        XCTAssertEqual(a[1].stacktrace.frames[1], Frame(filename: nil, function: "func22", raw_function: nil, lineno: 2, colno: nil, abs_path: "/some/path2.swift", instruction_addr: "0xe894"))
        XCTAssertEqual(a[1].stacktrace.frames[0], Frame(filename: nil, function: "func32", raw_function: nil, lineno: 3, colno: nil, abs_path: "/some/path3.swift", instruction_addr: "0x0350"))
    }

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
