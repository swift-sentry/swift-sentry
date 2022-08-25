import Foundation
import NIOCore

public enum EnvelopItemTypes: String {
    case event
    case transaction
    case attachment
    case session
    case sessions
    case userReport = "user_report"
    case clientReport = "client_report"
}

private enum NewlineData {
    static let newlineData = "\n".data(using: String.Encoding.utf8)!
}

public struct Envelope {
    enum EnvelopeError: Error {
        case tooManyErrorsOrTransactions(count: UInt64)
        case eventIdRequiredButNotPresentInEnvelope
        case envelopeToLarge(size: UInt64)
    }

    public var header: EnvelopeHeader
    public var items: [EnvelopeItem]
    public init(header: EnvelopeHeader, items: [EnvelopeItem]) {
        self.header = header
        self.items = items
    }
    /// checks some requirements from sentry for envelopes
    private func checkValidity() throws {
        var eventTransactionCount: UInt64 = 0
        var itemsReqEventIdCount: UInt64 = 0
        (eventTransactionCount, itemsReqEventIdCount) = items.reduce(
            into: (eventTransactionCount, itemsReqEventIdCount)
        ) { acc, aci in
            acc.0 += (aci.header.type == "transaction" || aci.header.type == "event") ? 1 : 0
            acc.1 += (aci.header.type == "user_report" || aci.header.type == "attachment") ? 1 : 0
        }
        guard eventTransactionCount < 2 else {
            throw EnvelopeError.tooManyErrorsOrTransactions(count: eventTransactionCount)
            // Envelope may contain at most one error or one transaction item
        }
        guard (itemsReqEventIdCount + eventTransactionCount) == 0 || header.eventId != nil else {
            throw EnvelopeError.eventIdRequiredButNotPresentInEnvelope
        }
    }
    /// Turns the items of the envelope to data and joins them to one data instance
    private func prepData(encoder: JSONEncoder) throws -> Data {
        let dumpedItems = try items.map { try $0.dump(encoder: encoder) }
        return dumpedItems.reduce(
            into:
                Data(capacity: dumpedItems.map { $0.count }.reduce(into: 0) { $0 += $1 })
        ) {
            $0.append($1)
        }
    }
    /// Turns the envelope into data in the correct format for sentry
    public func dump(encoder: JSONEncoder) throws -> Data {
        try checkValidity()
        var returnData = try encoder.encode(header) + NewlineData.newlineData
        returnData.append(try prepData(encoder: encoder))
        guard returnData.count <= Sentry.maxEnvelopeUncompressedSize else {
            throw EnvelopeError.envelopeToLarge(size: UInt64(returnData.count))
        }
        return returnData
    }
}

public struct EnvelopeHeader: Codable {
    private static let RFC3339DateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }()

    fileprivate let eventId: UUID?
    fileprivate let dsn: String?
    fileprivate let sdk: String?
    fileprivate let sentAt: String = ""
    public init(eventId: UUID?, dsn: String?, sdk: String?) {
        self.eventId = eventId
        self.dsn = dsn
        self.sdk = sdk
    }

    private enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case dsn
        case sdk
        case sentAt = "sent_at"
    }

    public func encode(to encoder: Encoder) throws {
        var container =
            encoder
            .container(keyedBy: CodingKeys.self)
        if let eventId = eventId {
            try container.encode(eventId, forKey: CodingKeys.eventId)
        }
        if let dsn = dsn {
            try container.encode(dsn, forKey: CodingKeys.dsn)
        }
        if let sdk = sdk {
            try container.encode(sdk, forKey: CodingKeys.sdk)
        }
        try container.encode(EnvelopeHeader.RFC3339DateFormatter.string(from: Date()), forKey: CodingKeys.sentAt)
    }
}

public struct EnvelopeItemHeader: Codable {
    fileprivate let type: String
    fileprivate var length: UInt64
    fileprivate let filename: String?
    fileprivate let contentType: String?
    public init(type: String, length: UInt64 = 0, filename: String?, contentType: String?) {
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

public struct EnvelopeItem {
    public enum EnvelopeItemError: Error {
        case attachmentToLarge(size: UInt64)
        case eventOrTransactionToLarge(size: UInt64)
        case sizeMissmatch(givenSize: UInt64, actualSize: UInt64)
    }

    fileprivate var header: EnvelopeItemHeader
    fileprivate let data: Data
    public init(header: EnvelopeItemHeader, data: Data) {
        self.header = header
        self.header.length = UInt64(data.count)
        self.data = data
    }

    public func dump(encoder: JSONEncoder) throws -> Data {
        let returnData = try encoder.encode(header) + NewlineData.newlineData + data + NewlineData.newlineData
        guard header.type != "attachment" || returnData.count <= Sentry.maxEachAtachment else {
            throw EnvelopeItemError.attachmentToLarge(
                size: UInt64(returnData.count)
            )
        }
        guard
            (header.type != "event" && header.type != "transaction")
                || (returnData.count <= Sentry.maxEventAndTransaction)
        else {
            throw EnvelopeItemError.eventOrTransactionToLarge(
                size: UInt64(returnData.count)
            )
        }
        return returnData
    }
}

public struct Attachment: CustomStringConvertible {
    public enum AttachmentError: Error {
        /// This error shouldn't be able to be thrown, but it prevents an
        /// forceful unwrapping from crashing the application
        case noDataOrFilenameOrPath
        /// Error in case the File on Disk of the Attachment couldn't be reaad for some reason
        case fileReadFailed
    }

    public static let defaultContentType = "application/octet-stream"
    fileprivate let filename: String
    fileprivate let payload: AttachmentPayload
    fileprivate let contentType: String
    public var description: String {
        "Attachment: \(filename)"
    }
    /// converts the Attachment to an EnvelopeItem
    /// if the Attachment is a FileAttachment, the file gets read at this point
    public func toEnvelopeItem() throws -> EnvelopeItem {
        var tempData = try payload.dump()
        if tempData.count > Sentry.maxAttachmentSize {
            tempData.removeAll()
        }
        return EnvelopeItem(
            header: EnvelopeItemHeader(
                type: "attachment",
                length: UInt64(tempData.count),
                filename: filename,
                contentType: contentType
            ),
            data: tempData
        )
    }
    /// Constructs an Attachment with a filename and the given data
    public init(data: Data, filename: String, contentType: String = Attachment.defaultContentType) {
        self.filename = filename
        payload = .fromPayload([UInt8](data))
        self.contentType = contentType
    }
    /// Constructs an Attachment from a file on disk, if no filename is given, one gets
    /// inferred from path
    public init(path: String, filename: String? = nil, contentType: String = Attachment.defaultContentType) throws {
        var path = path
        if let filename = filename {
            self.filename = filename
        } else {
            let tmep = path.components(separatedBy: "/")
            guard let filename = tmep.last else {
                throw AttachmentError.noDataOrFilenameOrPath
            }
            self.filename = filename
            path = tmep.dropLast().joined(separator: "/")
        }

        payload = .fromFile(path, self.filename)
        self.contentType = contentType
    }
    /// Contructs an Attachment from a file on disk, without inferring the filename
    public init(path: String? = nil, filename: String, contentType: String = Attachment.defaultContentType) {
        self.filename = filename
        payload = .fromFile(path, filename)
        self.contentType = contentType
    }

    public enum AttachmentPayload {
        case fromPayload([UInt8])
        case fromFile(String?, String)
        public func dump() throws -> Data {
            switch self {
            case let .fromFile(path, filename):
                do {
                    return try Data(contentsOf: URL(fileURLWithPath: (path ?? "") + filename))
                } catch {
                    throw AttachmentError.fileReadFailed
                }
            case let .fromPayload(data):
                return Data(data)
            }
        }
    }
}

#if swift(>=5.5)
    extension Attachment.AttachmentPayload: Sendable {}

    extension Attachment: Sendable {}
#endif
