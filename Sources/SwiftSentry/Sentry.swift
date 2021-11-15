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
            environment: self.environment,
            exception: exceptions,
            breadcrumbs: Breadcrumbs(values: SentryLoggingProxy.last),
            user: nil
        )

        sendEvent(event: event)
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
