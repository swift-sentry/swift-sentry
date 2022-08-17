import Foundation
import Logging
// import NIO

public struct SentryLogHandler: LogHandler {
    private let label: String
    private let sentry: Sentry
    public var metadata = Logger.Metadata()
    public var logLevel: Logger.Level

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            metadata[metadataKey]
        }
        set {
            metadata[metadataKey] = newValue
        }
    }

    public init(label: String, sentry: Sentry, level: Logger.Level) {
        self.label = label
        self.sentry = sentry
        logLevel = level
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let metadataEscaped = metadata.map { $0.merging(self.metadata, uniquingKeysWith: { a, _ in a }) } ?? self.metadata
        let tags = metadataEscaped.mapValues { "\($0)" }
        if let filenameValue = metadataEscaped["AttachmentFileName"] {
            switch filenameValue {
            case let .string(filename):
                if let attachmentDataValue = metadataEscaped["AttachmentData"] {
                    switch attachmentDataValue {
                    case let .stringConvertible(dataCon):
                        if dataCon is Data {
                            do {
                                let data = dataCon as! Data
                                let uid = UUID()
                                let attachemnt: Attachment = .init(data: data, filename: filename)
                                let eventData = try JSONEncoder().encode(
                                    Event(
                                        event_id: uid,
                                        timestamp: Date().timeIntervalSince1970,
                                        level: Level(from: level),
                                        logger: source,
                                        transaction: metadataEscaped["transaction"]?.description,
                                        server_name: nil,
                                        release: nil,
                                        tags: tags.isEmpty ? nil : tags,
                                        environment: nil,
                                        message: .raw(message: message.description),
                                        exception: nil,
                                        breadcrumbs: nil,
                                        user: nil
                                    )
                                )
                                let envo: Envelope = .init(
                                    header: .init(
                                        eventId: uid,
                                        dsn: nil,
                                        sdk: nil
                                    ),
                                    items: [
                                        try .init(
                                            header: .init(
                                                type: "event",
                                                length: UInt64(eventData.count),
                                                filename: nil,
                                                contentType: "application/json"
                                            ), data: eventData
                                        ),
                                        try attachemnt.toEnvelopeItem(),
                                    ]
                                )
                                sentry.capture(envelope: envo)
                                return
                            } catch {
                                break
                            }
                        }
                    default:
                        break
                    }
                }
                if let attachmentPathValue = metadataEscaped["AttachmentPath"] {
                    switch attachmentPathValue {
                    case let .string(path):
                        do {
                            let uid = UUID()
                            let attachemnt: Attachment = try .init(path: path, filename: filename)
                            let eventData = try JSONEncoder().encode(
                                Event(
                                    event_id: uid,
                                    timestamp: Date().timeIntervalSince1970,
                                    level: Level(from: level),
                                    logger: source,
                                    transaction: metadataEscaped["transaction"]?.description,
                                    server_name: nil,
                                    release: nil,
                                    tags: tags.isEmpty ? nil : tags,
                                    environment: nil,
                                    message: .raw(message: message.description),
                                    exception: nil,
                                    breadcrumbs: nil,
                                    user: nil
                                )
                            )
                            let envo: Envelope = .init(
                                header: .init(
                                    eventId: uid,
                                    dsn: nil,
                                    sdk: nil
                                ),
                                items: [
                                    try .init(
                                        header: .init(
                                            type: "event",
                                            length: UInt64(eventData.count),
                                            filename: nil,
                                            contentType: "application/json"
                                        ), data: eventData
                                    ),
                                    try attachemnt.toEnvelopeItem(),
                                ]
                            )
                            sentry.capture(envelope: envo)
                            return
                        } catch {
                            break
                        }
                    default:
                        break
                    }
                }
            default:
                break
            }
        }
        if let attachmentPathValue = metadataEscaped["AttachmentPath"] {
            switch attachmentPathValue {
            case let .string(path):
                do {
                    let uid = UUID()
                    let attachemnt: Attachment = try .init(path: path)
                    let eventData = try JSONEncoder().encode(
                        Event(
                            event_id: uid,
                            timestamp: Date().timeIntervalSince1970,
                            level: Level(from: level),
                            logger: source,
                            transaction: metadataEscaped["transaction"]?.description,
                            server_name: nil,
                            release: nil,
                            tags: tags.isEmpty ? nil : tags,
                            environment: nil,
                            message: .raw(message: message.description),
                            exception: nil,
                            breadcrumbs: nil,
                            user: nil
                        )
                    )
                    let envo: Envelope = .init(
                        header: .init(
                            eventId: uid,
                            dsn: nil,
                            sdk: nil
                        ),
                        items: [
                            try .init(
                                header: .init(
                                    type: "event",
                                    length: UInt64(eventData.count),
                                    filename: nil,
                                    contentType: "application/json"
                                ), data: eventData
                            ),
                            try attachemnt.toEnvelopeItem(),
                        ]
                    )
                    sentry.capture(envelope: envo)
                    return
                } catch {
                    break
                }
            default:
                break
            }
        }
        sentry.capture(
            message: message.description,
            level: Level(from: level),
            logger: source,
            transaction: metadataEscaped["transaction"]?.description,
            tags: tags.isEmpty ? nil : tags,
            file: file,
            filePath: nil,
            function: function,
            line: Int(line),
            column: nil
        )
    }
}
