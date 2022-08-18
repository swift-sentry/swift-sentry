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
                let eventData = try makeEventData(
                    message: message.description,
                    level: Level(from: level),
                    uid: uid,
                    servername: sentry.servername,
                    release: sentry.release,
                    environment: sentry.environment,
                    logger: source,
                    transaction: metadataEscaped["transaction"]?.description,
                    tags: tags.isEmpty ? nil : tags,
                    file: file,
                    function: function,
                    line: Int(line)
                )
                let envelope: Envelope = .init(header: .init(eventId: uid, dsn: nil, sdk: nil), items: [
                    .init(
                        header: .init(type: "event", filename: nil, contentType: "application/json"),
                        data: eventData
                    ),
                    attachment.toEnvelopeItemNoThrow(),
                ].compactMap { $0 })
                sentry.capture(envelope: envelope)
                return
            } catch {}
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
