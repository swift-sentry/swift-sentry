import Foundation
import Logging

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
        if let attachment = evalMetadata(metadata: metadataEscaped) {
            let uid = UUID()
            do {
                let eventData = try JSONEncoder().encode(Event(
                    event_id: uid,
                    timestamp: Date().timeIntervalSince1970,
                    level: Level(from: level),
                    logger: source,
                    transaction: metadataEscaped["transaction"]?.description,
                    server_name: sentry.servername,
                    release: sentry.release,
                    tags: tags.isEmpty ? nil : tags,
                    environment: sentry.environment,
                    message: .raw(message: message.description),
                    exception: nil,
                    breadcrumbs: nil,
                    user: nil
                ))
                let envelope: Envelope = .init(header: .init(eventId: uid, dsn: nil, sdk: nil), items: [
                    try .init(
                        header: .init(type: "event", length: UInt64(eventData.count), filename: nil, contentType: "application/json"),
                        data: eventData
                    ),
                    try attachment.toEnvelopeItem(),
                ])
                sentry.capture(envelope: envelope)
            } catch {}
            return
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
