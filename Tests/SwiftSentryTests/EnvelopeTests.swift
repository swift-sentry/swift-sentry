import Foundation
import NIOCore
@testable import SwiftSentry
import Testing

struct EnvelopeTests {
    private let eventUUID = UUID(uuidString: "01234567-ABCD-AAAA-BBBB-ABCDEFABCDEF")!

    /// Writes the envelope and splits it into its newline separated lines.
    private func writeLines(
        _ envelope: Envelope,
        maxAttachmentSize: Int = Sentry.defaultMaxAttachmentSize,
        dsn: String? = nil
    ) throws -> [String] {
        var buffer = ByteBuffer()
        try envelope.write(into: &buffer, encoder: JSONEncoder(), maxAttachmentSize: maxAttachmentSize, dsn: dsn)
        return String(buffer: buffer).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func object(_ line: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    /// Creates an empty temporary directory and passes it to `body`, removing it afterwards.
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @Test
    func `envelope without attachments`() throws {
        let envelope = Envelope(event: Event(event_id: eventUUID, message: .raw(message: "hi")))
        let lines = try writeLines(envelope, dsn: "https://public@sentry.example.com/1")
        try #require(lines.count == 3)

        let header = try object(lines[0])
        #expect(header["event_id"] as? String == "01234567abcdaaaabbbbabcdefabcdef")
        #expect(header["dsn"] as? String == "https://public@sentry.example.com/1")
        #expect(header["sent_at"] is String)

        let itemHeader = try object(lines[1])
        #expect(itemHeader["type"] as? String == "event")
        #expect(itemHeader["length"] as? Int == lines[2].utf8.count)
        #expect(itemHeader["filename"] == nil)

        let payload = try object(lines[2])
        #expect(payload["event_id"] as? String == "01234567abcdaaaabbbbabcdefabcdef")
        #expect(payload["message"] as? String == "hi")
    }

    @Test
    func `envelope header omits nil fields`() throws {
        let data = try JSONEncoder().encode(EnvelopeHeader(eventId: nil, dsn: nil))
        let header = try object(#require(String(bytes: data, encoding: .utf8)))
        #expect(Set(header.keys) == ["sent_at"])
        let sentAt = try #require(header["sent_at"] as? String)
        #expect(sentAt.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/) != nil, "\(sentAt)")
    }

    @Test
    func `envelope with data attachment`() throws {
        let attachment = Attachment(data: Array("payload".utf8), filename: "log.txt", contentType: "text/plain")
        let envelope = Envelope(event: Event(event_id: eventUUID), attachments: [attachment])
        #expect(envelope.attachments?.count == 1)

        let lines = try writeLines(envelope)
        try #require(lines.count == 5)
        let attachmentHeader = try object(lines[3])
        #expect(attachmentHeader["type"] as? String == "attachment")
        #expect(attachmentHeader["length"] as? Int == 7)
        #expect(attachmentHeader["filename"] as? String == "log.txt")
        #expect(attachmentHeader["content_type"] as? String == "text/plain")
        #expect(lines[4] == "payload")
    }

    @Test
    func `oversized attachment is skipped`() throws {
        let small = Attachment(data: Array("ok".utf8), filename: "small.txt")
        let large = Attachment(data: Array("too large".utf8), filename: "large.txt")
        let envelope = Envelope(event: Event(event_id: eventUUID), attachments: [large, small])

        let lines = try writeLines(envelope, maxAttachmentSize: 5)
        try #require(lines.count == 5)
        #expect(try object(lines[3])["filename"] as? String == "small.txt")
        #expect(lines[4] == "ok")
    }

    @Test
    func `unreadable attachment is skipped`() throws {
        let missing = Attachment(directory: "/nonexistent-directory/", filename: "missing.txt")
        let envelope = Envelope(event: Event(event_id: eventUUID), attachments: [missing])
        #expect(try writeLines(envelope).count == 3)
    }

    @Test
    func `attachment from directory and filename`() throws {
        try withTemporaryDirectory { dir in
            try "from disk".write(to: dir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

            let attachment = Attachment(directory: dir.path + "/", filename: "file.txt")
            #expect(attachment.description == "Attachment: file.txt")
            let lines = try writeLines(Envelope(event: Event(event_id: eventUUID), attachments: [attachment]))
            try #require(lines.count == 5)
            #expect(lines[4] == "from disk")
        }
    }

    @Test
    func `attachment infers filename from path`() throws {
        try withTemporaryDirectory { dir in
            let file = dir.appendingPathComponent("inferred.txt")
            try "inferred".write(to: file, atomically: true, encoding: .utf8)

            let attachment = try Attachment(path: file.path)
            #expect(attachment.description == "Attachment: inferred.txt")
            let lines = try writeLines(Envelope(event: Event(event_id: eventUUID), attachments: [attachment]))
            try #require(lines.count == 5, "Attachment was not written")
            #expect(try object(lines[3])["filename"] as? String == "inferred.txt")
            #expect(lines[4] == "inferred")
        }
    }

    @Test
    func `envelope error description`() {
        #expect(EnvelopeError.envelopeToLarge(size: 12).description == "EnvelopeError.envelopeToLarge(size: 12)")
    }
}
