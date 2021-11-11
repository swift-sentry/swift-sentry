//
//  SentryLoggingProxy.swift
//  SwiftSentry
//
//  Created by AZm87 on 24.06.21.
//

import Foundation
import Logging

public class SentryLoggingProxy: LogHandler {
    private var next: LogHandler
    // static var last = [(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt, timestamp: Double)]()
    static var last = [Breadcrumb]()

    public init(next: LogHandler) {
        self.next = next
    }

    public var metadata: Logger.Metadata {
        get { next.metadata }
        set { next.metadata = newValue }
    }

    public var logLevel: Logger.Level {
        get { next.logLevel }
        set { next.logLevel = newValue }
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { next[metadataKey: key] }
        set { next[metadataKey: key] = newValue }
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        next.log(level: level, message: message, metadata: metadata, source: source, file: file, function: function, line: line)

        let separator: Substring = file.contains("Sources") ? "Sources" : "Tests"
        let path = file.split(separator: "/").split(separator: separator).last?.joined(separator: "/") ?? file

        var text = "[\(level.rawValue.uppercased())] \(message.description) <\(source).\(function)> in (\(path):\(line))"

        let metadataEscaped = (metadata ?? [:]).merging(self.metadata, uniquingKeysWith: { (a, _) in a })

        if !metadataEscaped.isEmpty {
            text += " [" + metadataEscaped.sorted(by: { $0.0 < $1.0 }).map({ "\($0.description): \($1)" }).joined(separator: ", ") + "]"
        }

        SentryLoggingProxy.last.append(Breadcrumb(message: text, level: Level(from: level), timestamp: Date().timeIntervalSince1970))

        if SentryLoggingProxy.last.count > 10 {
            SentryLoggingProxy.last.removeFirst()
        }
    }
}
