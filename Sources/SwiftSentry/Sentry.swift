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
    internal static let VERSION = "SentrySwift/0.1.0"

    private let dns: Dsn
    private var httpClient: HTTPClient
    internal var servername: String?
    internal var release: String?
    internal var environment: String?

    public init(
        dns: String,
        httpClient: HTTPClient = HTTPClient(eventLoopGroupProvider: .createNew),
        servername: String? = Host.current().localizedName,
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

    public func captureError(error: Error) {
        let edb = ExceptionDataBag(
            type: "\(error.self)",
            value: error.localizedDescription,
            stacktrace: nil
        )

        let exceptions = Exceptions(values: [edb])

        let event = Event(
            event_id: Event.generateEventId(),
            timestamp: Date().timeIntervalSince1970,
            level: .error,
            server_name: self.servername,
            release: nil,
            tags: nil,
            environment: self.environment,
            exception: exceptions,
            breadcrumbs: nil,
            user: nil
        )

        sendEvent(event: event)
    }

    private func parseStacktrace(lines: [Substring]) -> [(msg: String, stacktace: Stacktrace)] {
        var result = [(msg: String, stacktace: Stacktrace)]()

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
                    let path = String(line[posAt.upperBound ..< posColon])
                    let lineno = Int(line[line.index(posColon, offsetBy: 1) ..< line.endIndex])

                    frames.insert(Frame(filename: nil, function: functionName, raw_function: nil, lineno: lineno, colno: nil, abs_path: path, instruction_addr: addr), at: 0)
                } else {
                    frames.insert(Frame(filename: nil, function: nil, raw_function: line, lineno: nil, colno: nil, abs_path: nil, instruction_addr: nil), at: 0)
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

        return result
    }

    public func uploadStackTrace(path: String) throws {
        // read all lines from the error log
        let content = try String(contentsOfFile: path)

        // empty the error log (we don't want to send events twice)
        try "".write(toFile: path, atomically: true, encoding: .utf8)

        for exception in parseStacktrace(lines: content.split(separator: "\n")) {
            sendEvent(
                event: Event(
                    event_id: Event.generateEventId(),
                    timestamp: Date().timeIntervalSince1970,
                    level: .fatal,
                    server_name: servername,
                    release: release,
                    tags: nil,
                    environment: environment,
                    exception: Exceptions(values: [ExceptionDataBag(type: "FatalError", value: exception.msg, stacktrace: exception.stacktace)]),
                    breadcrumbs: nil,
                    user: nil
                )
            )
        }
    }

    internal func sendEvent(event: Event) {
        guard let data = try? JSONEncoder().encode(event) else {
            print("Can't encode sentry event")
            return
        }

        guard var request = try? HTTPClient.Request(url: dns.getStoreApiEndpointUrl(), method: .POST) else {
            print("Can't create request")
            return
        }

        request.headers.replaceOrAdd(name: "Content-Type", value: "application/json")
        request.headers.replaceOrAdd(name: "User-Agent", value: Sentry.VERSION)
        request.headers.replaceOrAdd(name: "X-Sentry-Auth", value: self.dns.getAuthHeader())
        request.body = HTTPClient.Body.data(data)

        _ = httpClient.execute(request: request).map({ resp -> Void in
            guard var body = resp.body, let text = body.readString(length: body.readableBytes /* , encoding: String.Encoding.utf8 */ ) else {
                print("No response body \(resp.status)")
                return ()
            }

            print("\(text) \(resp.status)")
            return ()
        })
    }
}
