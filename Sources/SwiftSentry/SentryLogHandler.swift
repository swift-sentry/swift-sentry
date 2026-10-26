public import Logging
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct SentryLogHandler: LogHandler, Sendable {
    private let label: String
    private let sentry: Sentry
    public var metadata: Logger.Metadata
    public var logLevel: Logger.Level
    public var metadataProvider: Logger.MetadataProvider?

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            metadata[metadataKey]
        }
        set {
            metadata[metadataKey] = newValue
        }
    }

    public init(
        label: String,
        sentry: Sentry,
        level: Logger.Level,
        metadata: Logger.Metadata = [:],
        metadataProvider: Logger.MetadataProvider? = nil
    ) {
        self.label = label
        self.sentry = sentry
        logLevel = level
        self.metadata = metadata
        self.metadataProvider = metadataProvider
    }

    public func log(event: LogEvent) {
        let metadataEscaped = (event.metadata ?? [:])
            .merging(self.metadata, uniquingKeysWith: { a, _ in a })
            .merging(self.metadataProvider?.get() ?? [:], uniquingKeysWith: { a, _ in a })
        let tags = metadataEscaped.mapValues { "\($0)" }
        let uid = UUID()
        let frame = Frame(
            filename: event.file,
            function: event.function,
            raw_function: nil,
            lineno: Int(event.line),
            colno: nil,
            abs_path: event.file,
            instruction_addr: nil
        )
        let stacktrace = Stacktrace(frames: [frame])
        var expections = [ExceptionDataBag(
            type: event.message.description,
            value: nil,
            stacktrace: stacktrace
        )]
        if let error = event.error {
            expections.append(ExceptionDataBag(
                type: String(describing: type(of: error)),
                value: String(describing: error),
                stacktrace: nil
            ))
        }
        let event = Event(
            event_id: uid,
            timestamp: Date().timeIntervalSince1970,
            level: .init(from: event.level),
            logger: event.source,
            transaction: metadataEscaped["transaction"]?.description,
            server_name: sentry.guts.servername,
            release: sentry.guts.release,
            tags: tags.isEmpty ? nil : tags,
            environment: sentry.guts.environment,
            message: .raw(message: event.message.description),
            exception: Exceptions(values: expections),
            breadcrumbs: nil,
            user: nil
        )
        let envelope = Envelope(
            event: event,
            attachments: metadataEscaped.values.compactMap {
                switch $0 {
                case .stringConvertible(let conv):
                    conv as? Attachment
                default:
                    nil
                }
            }
        )
        sentry.send(envelope: envelope)
    }
}
