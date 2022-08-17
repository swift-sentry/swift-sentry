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
            let frame = Frame(filename: file, function: function, raw_function: nil, lineno: Int(line), colno: nil, abs_path: nil, instruction_addr: nil)
            let stacktrace = Stacktrace(frames: [frame])
            var envelope: Envelope = .init(
                header: .init(eventId: uid, dsn: nil, sdk: nil),
                items: []
            )
            do {
                let eventData = try JSONEncoder().encode(
                    LimitedEvent(
                        event_id: uid,
                        level: Level(from: level),
                        logger: source,
                        transaction: metadataEscaped["transaction"]?.description,
                        server_name: sentry.servername,
                        release: sentry.release,
                        tags: tags.isEmpty ? nil : tags,
                        environment: sentry.environment,
                        message: .raw(message: message.description),
                        exception: Exceptions(values: [ExceptionDataBag(type: message.description, value: nil, stacktrace: stacktrace)])
                    )
                )
                envelope.items.append(try .init(
                    header: .init(type: "event", length: UInt64(eventData.count), filename: nil, contentType: "application/json"),
                    data: eventData
                ))
            } catch {
                return
            }
            do {
                envelope.items.append(try attachment.toEnvelopeItem())
            } catch {}
            sentry.capture(envelope: envelope)
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
