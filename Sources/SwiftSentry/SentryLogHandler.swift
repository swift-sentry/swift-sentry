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
            self.metadata[metadataKey]
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
        let metadataEscaped = metadata.map ({ $0.merging(self.metadata, uniquingKeysWith: { a, _ in a } )}) ?? self.metadata
        let tags = metadataEscaped.mapValues({ "\($0)" })
        
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
