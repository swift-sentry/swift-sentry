//
//  Sentry.swift
//  SwiftSentry
//
//  Created by AZm87 on 24.06.21.
//

import Foundation
import AsyncHTTPClient
import NIO

public struct Sentry {
    enum SwiftSentryError: Error {
        case CantEncodeEvent
        case CantCreateRequest
        case NoResponseBody(status: UInt)
        case InvalidArgumentException(_ msg: String)
    }

    internal static let VERSION = "SentrySwift/0.1.0"

    private let dns: Dsn
    private var httpClient: HTTPClient
    internal var servername: String?
    internal var release: String?
    internal var environment: String?

    public init(
        dns: String,
        httpClient: HTTPClient = HTTPClient(eventLoopGroupProvider: .createNew),
        servername: String? = ProcessInfo.processInfo.hostName,
        release: String? = nil,
        environment: String? = nil
    ) throws {
        self.dns = try Dsn(fromString: dns)
        self.httpClient = httpClient
        self.servername = servername
        self.release = release
        self.environment = environment
    }

    public func shutdown() throws {
        try httpClient.syncShutdown()
    }

    @discardableResult
    public func captureError(error: Error, eventLoop: EventLoop? = nil) -> EventLoopFuture<UUID> {
        let edb = ExceptionDataBag(
            type: "\(error.self)",
            value: error.localizedDescription,
            stacktrace: nil
        )

        let exceptions = Exceptions(values: [edb])

        let event = Event(
            event_id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            level: .error,
            logger: nil,
            transaction: nil,
            server_name: self.servername,
            release: self.release,
            tags: nil,
            environment: self.environment,
            message: .raw(message: "\(error.localizedDescription)"),
            exception: exceptions,
            breadcrumbs: nil,
            user: nil
        )

        return sendEvent(event: event, eventLoop: eventLoop)
    }

    internal static func parseStacktrace(lines: [Substring]) -> [(msg: String, stacktrace: Stacktrace)] {
        var result = [(msg: String, stacktrace: Stacktrace)]()

        var stacktraceFound = false
        var frames = [Frame]()
        var errorMessage = [String]()

        for l in lines {
            let line = l.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                continue
            }

            switch (line.starts(with: "0x"), stacktraceFound) {
            case (true, _):
                // found a line of the stacktrace
                stacktraceFound = true

                if let posComma = line.firstIndex(of: ","), let posAt = line.range(of: " at /"), let posColon = line.lastIndex(of: ":") {
                    let addr = String(line[line.startIndex ..< posComma])
                    let functionName = String(line[line.index(posComma, offsetBy: 2) ..< posAt.lowerBound])
                    let path = String(line[line.index(before: posAt.upperBound) ..< posColon])
                    let lineno = Int(line[line.index(posColon, offsetBy: 1) ..< line.endIndex])

                    frames.insert(Frame(filename: nil, function: functionName, raw_function: nil, lineno: lineno, colno: nil, abs_path: path, instruction_addr: addr), at: 0)
                } else {
                    frames.insert(Frame(filename: nil, function: nil, raw_function: nil, lineno: nil, colno: nil, abs_path: nil, instruction_addr: line), at: 0)
                }
            case (false, false):
                // found another header line
                errorMessage.append(line)
            case (false, true):
                // if we find a non stacktrace line after a stacktrace, its a new error -> send current error to sentry and start a new error event
                result.append((errorMessage.joined(separator: "\n"), Stacktrace(frames: frames)))
                stacktraceFound = false
                frames = [Frame]()
                errorMessage = [line]
            }
        }

        if !frames.isEmpty || !errorMessage.isEmpty {
            result.append((errorMessage.joined(separator: "\n"), Stacktrace(frames: frames)))
        }

        return result
    }

    @discardableResult
    public func uploadStackTrace(path: String, eventLoop: EventLoop? = nil) throws -> EventLoopFuture<[UUID]> {
        let eventLoop = eventLoop ?? httpClient.eventLoopGroup.next()

        // read all lines from the error log
        guard let content = try? String(contentsOfFile: path) else {
            return eventLoop.makeSucceededFuture([UUID]())
        }

        // empty the error log (we don't want to send events twice)
        try "".write(toFile: path, atomically: true, encoding: .utf8)

        return EventLoopFuture.whenAllSucceed(Sentry.parseStacktrace(lines: content.split(separator: "\n")).map({ exception in
            sendEvent(
                event: Event(
                    event_id: UUID(),
                    timestamp: Date().timeIntervalSince1970,
                    level: .fatal,
                    logger: nil,
                    transaction: nil,
                    server_name: servername,
                    release: release,
                    tags: nil,
                    environment: environment,
                    message: .raw(message: exception.msg),
                    exception: Exceptions(values: [ExceptionDataBag(type: "FatalError", value: exception.msg, stacktrace: exception.stacktrace)]),
                    breadcrumbs: nil,
                    user: nil
                ),
                eventLoop: eventLoop
            )
        }), on: eventLoop)
    }

    @discardableResult
    internal func sendEvent(event: Event, eventLoop: EventLoop? = nil) -> EventLoopFuture<UUID> {
        let eventLoop = eventLoop ?? httpClient.eventLoopGroup.next()

        guard let data = try? JSONEncoder().encode(event) else {
            return eventLoop.makeFailedFuture(SwiftSentryError.CantEncodeEvent)
        }

        guard var request = try? HTTPClient.Request(url: dns.getStoreApiEndpointUrl(), method: .POST) else {
            return eventLoop.makeFailedFuture(SwiftSentryError.CantCreateRequest)
        }

        request.headers.replaceOrAdd(name: "Content-Type", value: "application/json")
        request.headers.replaceOrAdd(name: "User-Agent", value: Sentry.VERSION)
        request.headers.replaceOrAdd(name: "X-Sentry-Auth", value: self.dns.getAuthHeader())
        request.body = HTTPClient.Body.data(data)

        return httpClient.execute(request: request, eventLoop: .delegate(on: eventLoop)).flatMapThrowing({ resp -> UUID in
            guard var body = resp.body, let id = body.getUUIDHexadecimalEncoded() else {
                throw SwiftSentryError.NoResponseBody(status: resp.status.code)
            }
            return id
        })
    }
}
