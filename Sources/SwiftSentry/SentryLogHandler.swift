//
//  SentryLogHandler.swift
//  SwiftSentry
//
//  Created by AZm87 on 15.11.21.
//

import Foundation
import Logging

public class SentryLogHandler: LogHandler {
    private let label: String
    private let sentry: Sentry
    public var metadata = Logger.Metadata()
    public var logLevel: Logger.Level
    private let sendLevel: Logger.Level
    private var lastBreadcrumps = [Breadcrumb]()
    private let breadcrumpCount: Int

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    public init(label: String, sentry: Sentry, breadcrumpLevel: Logger.Level, sendLevel: Logger.Level, breadcrumpCount: Int = 20) {
        self.label = label
        self.sentry = sentry
        self.logLevel = breadcrumpLevel
        self.sendLevel = sendLevel
        self.breadcrumpCount = breadcrumpCount
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
        if level < sendLevel {
            self.lastBreadcrumps.append(Breadcrumb(message: message.description, level: Level(from: level), timestamp: Date().timeIntervalSince1970))
            if self.lastBreadcrumps.count > breadcrumpCount {
                self.lastBreadcrumps.removeFirst()
            }
        } else {
            let tags: [String: String]?

            let metadataEscaped = (metadata ?? [:]).merging(self.metadata, uniquingKeysWith: { (a, _) in a })

            if !metadataEscaped.isEmpty {
                tags = metadataEscaped.reduce(into: [String: String](), {
                    $0[$1.key] = "\($1.value)"
                })
            } else {
                tags = nil
            }

            let event = Event(
                event_id: Event.generateEventId(),
                timestamp: Date().timeIntervalSince1970,
                level: Level.init(from: level),
                logger: label,
                server_name: sentry.servername,
                release: sentry.release,
                tags: tags,
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
                breadcrumbs: self.lastBreadcrumps.isEmpty ? nil : Breadcrumbs(values: self.lastBreadcrumps),
                user: nil
            )

            sentry.sendEvent(event: event)
        }
    }
}
