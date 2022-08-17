import Foundation
import NIOCore

public enum EnvelopItemTypes: String {
    case event
    case transaction
    case attachment
    case session
    case sessions
    case user_report
    case client_report
}

public enum NewlineData {
    static let newlineData = "\n".data(using: String.Encoding.utf8)!
}

public struct Envelope {
    enum EnvelopeError: Error {
        case TooManyErrorsOrTransactions(count: UInt64)
        case ItemsRequireEventIdButNoEventIdInEnvelopHeader
        case EnvelopeToLarge(size: UInt64)
    }

    public var header: EnvelopeHeader
    public var items: [EnvelopeItem]
    public init(header: EnvelopeHeader, items: [EnvelopeItem]) {
        self.header = header
        self.items = items
    }

    public func dump(encoder: JSONEncoder) throws -> Data {
        var event_transaction_count: UInt64 = 0
        var req_event_id: UInt64 = 0
        var returnData = try encoder.encode(header) + NewlineData.newlineData
        returnData.append(try items
            .map {
                if $0.header.type == "transaction" || $0.header.type == "event" {
                    event_transaction_count += 1
                } else if $0.header.type == "user_report" || $0.header.type == "attachment" {
                    req_event_id += 1
                }
                return try $0.dump(encoder: encoder)
            }
            .reduce(into: Data()) { acu, adi in
                acu.append(adi)
            })
        if event_transaction_count >= 2 {
            throw EnvelopeError.TooManyErrorsOrTransactions(count: event_transaction_count)
        }
        if (req_event_id + event_transaction_count) > 0, header.eventId == nil {
            throw EnvelopeError.ItemsRequireEventIdButNoEventIdInEnvelopHeader
        }
        if returnData.count > Sentry.maxEnvelopeUncompressedSize {
            throw EnvelopeError.EnvelopeToLarge(size: UInt64(returnData.count))
        }
        return returnData
    }
}

public struct EnvelopeHeader: Codable {
    public static let RFC3339DateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }()

    public var eventId: UUID?
    public var dsn: String?
    public var sdk: String?
    public var sentAt: String = ""
    public init(eventId: UUID?, dsn: String?, sdk: String?) {
        self.eventId = eventId
        self.dsn = dsn
        self.sdk = sdk
    }

    public enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case dsn
        case sdk
        case sentAt = "sent_at"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder
            .container(keyedBy: CodingKeys.self)
        if eventId != nil {
            try container.encode(eventId, forKey: .init(stringValue: "event_id")!)
        }
        if dsn != nil {
            try container.encode(dsn, forKey: .init(stringValue: "dsn")!)
        }
        if sdk != nil {
            try container.encode(sdk, forKey: .init(stringValue: "sdk")!)
        }
        try container.encode(EnvelopeHeader.RFC3339DateFormatter.string(from: Date()), forKey: .init(stringValue: "sent_at")!)
    }
}

public struct EnvelopeItemHeader: Codable {
    public var type: String
    public var length: UInt64
    public var filename: String?
    public var contentType: String?
    public init(type: String, length: UInt64, filename: String?, contentType: String?) {
        self.type = type
        self.length = length
        self.filename = filename
        self.contentType = contentType
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case length
        case filename
        case contentType = "content_type"
    }
}

public struct EnvelopeItem {
    public enum EnvelopeItemError: Error {
        case AttachmentToLarge(size: UInt64)
        case EventOrAttachmentToLarge(size: UInt64)
        case SizeMissmatch(givenSize: UInt64, actualSize: UInt64)
    }

    public var header: EnvelopeItemHeader
    public var data: Data
    public init(header: EnvelopeItemHeader, data: Data) throws {
        if header.length != UInt64(data.count) {
            throw EnvelopeItemError.SizeMissmatch(givenSize: header.length, actualSize: UInt64(data.count))
        }
        self.header = header
        self.data = data
    }

    public func dumpToString(encoder: JSONEncoder) throws -> String {
        let headerData = try encoder.encode(header)
        let returnString = String(data: headerData, encoding: String.Encoding.utf8)! + "\n" + String(data: data, encoding: String.Encoding.utf8)! + "\n"
        if header.type == "attachment", (headerData.count + 2 + data.count) > Sentry.maxEachAtachment {
            throw EnvelopeItemError.AttachmentToLarge(size: UInt64(headerData.count + 2 + data.count))
        }
        if !(header.type != "event" && header.type != "transaction"), (headerData.count + 2 + data.count) > Sentry.maxEventAndTransaction {
            throw EnvelopeItemError.EventOrAttachmentToLarge(size: UInt64(headerData.count + 2 + data.count))
        }
        return returnString
    }

    public func dump(encoder: JSONEncoder) throws -> Data {
        let returnData = try encoder.encode(header) + NewlineData.newlineData + data + NewlineData.newlineData
        assert(header.type != "attachment" || returnData.count <= Sentry.maxEachAtachment)
        assert((header.type != "event" && header.type != "transaction") || returnData.count <= Sentry.maxEventAndTransaction)
        return returnData
    }
}

public struct Attachment {
    public enum AttachmentError: Error {
        case NoDataOrFilenameOrPath
        case FileReadFailed
    }

    public static let defaultContentType = "application/octet-stream"
    public var filename: String
    public var payload: AttachmentPayload
    public var contentType: String
    public func toEnvelopeItem() throws -> EnvelopeItem {
        var tempData = try payload.dump()
        if tempData.count > Sentry.maxAttachmentSize {
            tempData.removeAll()
        }
        return try EnvelopeItem(header: EnvelopeItemHeader(type: "attachment", length: UInt64(tempData.count), filename: filename, contentType: contentType), data: tempData)
    }

    public init(data: Data, filename: String, contentType: String = Attachment.defaultContentType) {
        self.filename = filename
        payload = .fromPayload(data)
        self.contentType = contentType
    }

    public init(path: String, filename: String? = nil, contentType: String = Attachment.defaultContentType) throws {
        var path = path
        if let filename = filename {
            self.filename = filename
        } else {
            let tmep = path.components(separatedBy: "/")
            guard let filename = tmep.last else {
                throw AttachmentError.NoDataOrFilenameOrPath
            }
            self.filename = filename
            path = tmep.dropLast().joined(separator: "/")
        }

        payload = .fromFile(path, self.filename)
        self.contentType = contentType
    }

    public init(path: String, filenameNN: String, contentType: String = Attachment.defaultContentType) {
        filename = filenameNN
        payload = .fromFile(path, filename)
        self.contentType = contentType
    }

    public enum AttachmentPayload {
        case fromPayload(Data)
        case fromFile(String?, String)
        public func dump() throws -> Data {
            switch self {
            case let .fromFile(path, filename):
                do {
                    return try Data(contentsOf: URL(fileURLWithPath: (path ?? "") + filename))
                } catch {
                    throw AttachmentError.FileReadFailed
                }
            case let .fromPayload(data):
                return data
            }
        }
    }
}
