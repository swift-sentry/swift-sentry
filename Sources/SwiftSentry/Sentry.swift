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
    private static var instance: Sentry?

    public static func singleton() -> Sentry {
        instance!
    }

    private let dns: Dsn
    private var httpClient: HTTPClient?
    private var servername = ""
    private var environment = ""

    public init(url: String, eventLoop: EventLoopGroup, servername: String, environment: String) throws {
        self.dns = try Dsn(fromString: url)
        self.httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        self.servername = servername
        self.environment = environment
        Sentry.instance = self
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

    private func sendEvent(event: Event) {
        guard let data = try? JSONEncoder().encode(event) else {
            print("Can't encode sentry event")
            return
        }

        guard let client = httpClient else {
            print("Can't send sentry event")
            return
        }

        guard var request = try? HTTPClient.Request(url: dns.getStoreApiEndpointUrl(), method: .POST) else {
            print("Can't create request")
            return
        }

        request.headers.replaceOrAdd(name: "Content-Type", value: "application/json")
        request.headers.replaceOrAdd(name: "User-Agent", value: "SentrySwift/0.1.0")
        request.headers.replaceOrAdd(name: "X-Sentry-Auth", value: self.dns.getAuthHeader())
        request.body = HTTPClient.Body.data(data)

        _ = client.execute(request: request).map({ resp -> Void in
            guard var body = resp.body, let text = body.readString(length: body.readableBytes, encoding: .utf8) else {
                print("No response body \(resp.status)")
                return ()
            }

            print("\(text) \(resp.status)")
            return ()
        })
    }
}