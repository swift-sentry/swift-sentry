public import Foundation
import NIOCore
import NIOFoundationCompat

public struct EnvelopeError: Error, Equatable, CustomStringConvertible {
    enum Err: Error, Equatable {
        case envelopeToLarge(size: Int)
    }

    var error: Err

    public static func envelopeToLarge(size: Int) -> Self {
        Self(error: .envelopeToLarge(size: size))
    }

    public var description: String {
        switch error {
        case .envelopeToLarge(let size): "EnvelopeError.envelopeToLarge(size: \(size))"
        }
    }
}

public struct Envelope: Sendable {
    public enum ItemType: String, Sendable, Codable {
        case event
        case transaction
        case attachment
    }

    struct EventInfo: Sendable {
        enum Cause: Sendable {
            case event(Event)
            // Missing
            // case transaction(Transaction)
            // case feedback

            var id: UUID {
                switch self {
                case .event(let event):
                    event.event_id.rawValue
                }
            }

            var type: ItemType {
                switch self {
                case .event:
                    .event
                }
            }

            func encode(using encoder: JSONEncoder) throws -> Data {
                switch self {
                case .event(let event):
                    try encoder.encode(event)
                }
            }
        }

        var cause: Cause
        var attachments: [Attachment]
    }

    var event: EventInfo?
    // Missing
    // var span: Span?
    // var log: Logs?
    // var metric: Metrics?
    // var sessions: [Session]
    // var checkIn: CheckIn?
    // var clientReports: [ClientReport]
    // var replay: (ReplayEvent, ReplayRecording)?

    public var attachments: [Attachment]? {
        event?.attachments
    }

    public init(event: Event, attachments: [Attachment] = []) {
        self.event = .init(cause: .event(event), attachments: attachments)
    }

    func header(dsn: String?) -> EnvelopeHeader {
        return EnvelopeHeader(eventId: event?.cause.id, dsn: dsn)
    }

    func write(
        into buffer: inout ByteBuffer,
        encoder: JSONEncoder,
        maxAttachmentSize: Int = Sentry.defaultMaxAttachmentSize,
        dsn: String? = nil
    ) throws {
        try encoder.encode(self.header(dsn: dsn), into: &buffer)
        if let event {
            let data = try event.cause.encode(using: encoder)
            let header = ItemHeader(
                type: event.cause.type,
                length: data.count,
                filename: nil,
                contentType: nil
            )
            buffer.writeInteger(newLineByte)
            try encoder.encode(header, into: &buffer)
            buffer.writeInteger(newLineByte)
            buffer.writeData(data)
            for attachment in event.attachments {
                let indexStart = buffer.writerIndex
                do {
                    let data: Data = try attachment.payload.dump()
                    guard data.count <= maxAttachmentSize else {
                        continue
                    }
                    let header = ItemHeader(
                        type: .attachment,
                        length: data.count,
                        filename: attachment.filename,
                        contentType: attachment.contentType
                    )
                    buffer.writeInteger(newLineByte)
                    try encoder.encode(header, into: &buffer)
                    buffer.writeInteger(newLineByte)
                    buffer.writeData(data)
                    guard buffer.writerIndex <= Sentry.maxEnvelopeUncompressedSize else {
                        throw EnvelopeError.envelopeToLarge(size: buffer.writerIndex)
                    }
                } catch {
                    buffer.moveWriterIndex(to: indexStart)
                }
            }
        }
        guard buffer.writerIndex <= Sentry.maxEnvelopeUncompressedSize else {
            throw EnvelopeError.envelopeToLarge(size: buffer.writerIndex)
        }
    }
}

let newLineByte = Character("\n").asciiValue!

struct EnvelopeHeader: Encodable, Sendable {
    private static let RFC3339DateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }()

    let eventId: EventId?
    let dsn: String?

    init(eventId: UUID?, dsn: String?) {
        self.eventId = eventId.map(EventId.init)
        self.dsn = dsn
    }

    private enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case dsn
        case sentAt = "sent_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let eventId {
            try container.encode(eventId, forKey: CodingKeys.eventId)
        }
        if let dsn {
            try container.encode(dsn, forKey: CodingKeys.dsn)
        }
        try container.encode(EnvelopeHeader.RFC3339DateFormatter.string(from: Date()), forKey: CodingKeys.sentAt)
    }
}

extension Envelope {
    struct ItemHeader: Codable, Sendable {
        let type: ItemType
        fileprivate var length: Int
        fileprivate let filename: String?
        fileprivate let contentType: String?

        init(type: ItemType = .event, length: Int = 0, filename: String?, contentType: String?) {
            self.type = type
            self.length = length
            self.filename = filename
            self.contentType = contentType
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case length
            case filename
            case contentType = "content_type"
        }
    }
}

public struct Attachment: CustomStringConvertible, Sendable {
    public enum AttachmentError: Error {
        /// Error in case the File on Disk of the Attachment couldn't be reaad for some reason
        case fileReadFailed
    }

    public static let defaultContentType = "application/octet-stream"
    fileprivate let filename: String?
    fileprivate let payload: AttachmentPayload
    fileprivate let contentType: String?
    public var description: String {
        "Attachment: \(filename, default: "(unnamed attachment)")"
    }

    /// Constructs an Attachment with a filename and the given data
    public init(data: any Sequence<UInt8> & Sendable, filename: String, contentType: String = Attachment.defaultContentType) {
        self.filename = filename
        payload = .fromPayload(data)
        self.contentType = contentType
    }

    /// Constructs an Attachment from a file on disk, if no filename is given, one gets
    /// inferred from path
    public init(path: String, filename: String? = nil, contentType: String = Attachment.defaultContentType) {
        let url = URL(filePath: path)
        self.filename = filename ?? url.lastPathComponent
        payload = .fromFile(url)
        self.contentType = contentType
    }

    /// Contructs an Attachment from a file on disk, without inferring the filename
    public init(directory: String? = nil, filename: String, contentType: String = Attachment.defaultContentType) {
        self.filename = filename
        let url = URL(filePath: directory ?? ".").appending(path: filename)
        payload = .fromFile(url)
        self.contentType = contentType
    }

    public enum AttachmentPayload: Sendable {
        case fromPayload(any Sequence<UInt8> & Sendable)
        case fromFile(URL)
        public func dump() throws -> Data {
            switch self {
            case .fromFile(let path):
                do {
                    return try Data(contentsOf: path)
                } catch {
                    throw AttachmentError.fileReadFailed
                }
            case .fromPayload(let data):
                return Data(data)
            }
        }
    }
}
