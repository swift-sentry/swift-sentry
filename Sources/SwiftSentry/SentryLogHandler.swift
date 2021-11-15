//
//  SentryLogHandler.swift
//  SwiftSentry
//
//  Created by AZm87 on 15.11.21.
//

import Foundation
import Logging

public struct SentryLogHandler: LogHandler {
    private let label: String
    private let sentry: Sentry
    public var metadata = Logger.Metadata()
    public var logLevel: Logger.Level

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    public init(label: String, sentry: Sentry, level: Logger.Level) {
        self.label = label
        self.sentry = sentry
        self.logLevel = level
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
        let breadcrumbs: Breadcrumbs?

        let metadataEscaped = (metadata ?? [:]).merging(self.metadata, uniquingKeysWith: { (a, _) in a })

        if !metadataEscaped.isEmpty {
            breadcrumbs = Breadcrumbs(
                values: metadataEscaped
                    .sorted(by: { $0.0 < $1.0 })
                    .map({ Breadcrumb(message: "\($0.description): \($1)", level: nil, timestamp: nil) })
            )
        } else {
            breadcrumbs = nil
        }

        let event = Event(
            event_id: Event.generateEventId(),
            timestamp: Date().timeIntervalSince1970,
            level: Level.init(from: level),
            server_name: sentry.servername,
            release: sentry.release,
            environment: sentry.environment,
            exception: Exceptions(
                values: [
                    ExceptionDataBag(
                        type: nil,
                        value: message.description,
                        stacktrace: Stacktrace(
                            frames: [
                                Frame(
                                    filename: nil,
                                    function: function,
                                    raw_function: nil,
                                    lineno: Int(line),
                                    colno: nil,
                                    abs_path: file,
                                    instruction_addr: nil
                                )
                            ]
                        )
                    )
                ]
            ),
            breadcrumbs: breadcrumbs,
            user: nil
        )

        sentry.sendEvent(event: event)
    }
}
