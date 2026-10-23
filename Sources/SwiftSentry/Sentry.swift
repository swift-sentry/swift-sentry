import AsyncHTTPClient
import Foundation
import NIO
import NIOFoundationCompat

func parseLimits(
    header: String,
    into limits: inout [Category: ContinuousClock.Instant],
    recieveTime: ContinuousClock.Instant
) {
    for limit in header.split(
        separator: ",",
        omittingEmptySubsequences: false
    ).map({ $0.trimming(while: { $0.isWhitespace }) }) {
        let component = limit.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard component.count >= 2, let retryAfter = Double(component[0]) else {
            continue
        }
        let categoriesComp = component[1]
        guard !categoriesComp.isEmpty else {
            for cat in Category.allCases {
                limits[cat] = max(
                    recieveTime.advanced(by: .seconds(retryAfter)),
                    limits[cat, default: recieveTime]
                )
            }
            continue
        }
        for cat in categoriesComp.split(
            separator: ";",
            omittingEmptySubsequences: false
        ).compactMap(Category.init) {
            limits[cat] = max(
                recieveTime.advanced(by: .seconds(retryAfter)),
                limits[cat, default: recieveTime]
            )
        }
    }
}

struct SentryEmission {
    let envelope: Envelope
    var cont: CheckedContinuation<UUID?, any Error>?

    mutating func process(
        client: HTTPClient,
        dsn: Dsn,
        maxAttachmentSize: Int,
        sdk: String?
    ) async throws -> [Category: ContinuousClock.Instant] {
        var bytes = ByteBuffer()
        try envelope.write(
            into: &bytes,
            encoder: JSONEncoder(),
            maxAttachmentSize: maxAttachmentSize,
            dsn: nil,
            sdk: sdk
        )
        var request = HTTPClientRequest(url: dsn.getEnvelopeApiEndpointUrl())
        request.method = .POST
        request.headers.replaceOrAdd(name: "Content-Type", value: "application/x-sentry-envelope")
        request.headers.replaceOrAdd(name: "User-Agent", value: Sentry.VERSION)
        request.headers.replaceOrAdd(name: "X-Sentry-Auth", value: dsn.getAuthHeader())
        request.body = .bytes(bytes)
        let response = try await client.execute(request, timeout: .seconds(60))
        let recv = ContinuousClock.now
        let rateLimitHeaders = response.headers["X-Sentry-Rate-Limits"]
        var rateLimits: [Category: ContinuousClock.Instant] = [:]
        for limitHeader in rateLimitHeaders {
            parseLimits(header: limitHeader, into: &rateLimits, recieveTime: recv)
        }
        let body = try? await response.body.collect(upTo: 50)
        switch response.status {
        case .tooManyRequests:
            cont.take()?.resume(throwing: Sentry.SwiftSentryError.rateLimited)
            guard rateLimits.isEmpty else { break }
            let retryAfter: Double
            if let retryAfterHeader = response.headers.first(name: "Retry-After") {
                guard let val = Double(retryAfterHeader) else {
                    break
                }
                retryAfter = val
            } else {
                retryAfter = 60
            }
            for cat in Category.allCases {
                rateLimits[cat] = recv.advanced(by: .seconds(retryAfter))
            }
        case let status where 200...299 ~= status.code:
            guard let body else {
                cont.take()?.resume(returning: nil)
                break
            }
            let dec = JSONDecoder()
            let resp = try? dec.decode(Sentry.SentryUUIDResponse.self, from: body)
            let uuid = resp?.id.flatMap { UUID(fromHexadecimalEncodedString: $0) }
            cont.take()?.resume(returning: uuid)
        default:
            cont.take()?.resume(throwing: Sentry.SwiftSentryError.otherServerError(status: response.status.code))
        }
        return rateLimits
    }

    func allowed(with limits: [Category: ContinuousClock.Instant]) -> Bool {
        if let ev = envelope.event {
            switch ev.cause.type {
            case .event:
                guard limits[.error, default: .now] <= .now,
                      limits[.default, default: .now] <= .now
                else {
                    return false
                }

            case .transaction:
                guard limits[.transaction, default: .now] <= .now else {
                    return false
                }

            case .attachment:
                break
            }
        }
        return true
    }
}

enum Category: Substring, CaseIterable, Hashable {
    case `default`
    case error
    case attachment
    case transaction
}

actor RateLimits {
    init(
        perCategory: [Category: ContinuousClock.Instant] = [:],
        waiter: UnsafeContinuation<Void, Never>? = nil,
        allowed: Int
    ) {
        self.perCategory = perCategory
        self.waiter = waiter
        self.allowed = allowed
    }

    var perCategory: [Category: ContinuousClock.Instant] = [:]
    var waiter: UnsafeContinuation<Void, Never>?
    var allowed: Int

    func merge(new limits: [Category: ContinuousClock.Instant]) {
        for (cat, until) in limits {
            guard let curLim = perCategory[cat] else {
                perCategory[cat] = until
                continue
            }
            perCategory[cat] = max(until, curLim)
        }
    }

    func allowed(_ event: SentryEmission) async throws(Sentry.SwiftSentryError) {
        guard event.allowed(with: perCategory) else {
            throw .rateLimited
        }
        if allowed > 0 {
            allowed -= 1
            return
        }
        assert(waiter == nil)
        await withUnsafeContinuation {
            waiter = $0
        }
        guard event.allowed(with: perCategory) else {
            end()
            throw .rateLimited
        }
    }

    func end(new limits: [Category: ContinuousClock.Instant]? = nil) {
        if let limits {
            merge(new: limits)
        }
        if let w = waiter.take() {
            w.resume()
        } else {
            allowed += 1
        }
    }
}

struct SentryGuts {
    let eventStream: AsyncStream<SentryEmission>
    let cont: AsyncStream<SentryEmission>.Continuation
    let dsn: Dsn
    let httpClient: HTTPClient
    let maxAttachmentSize: Int
    let servername: String?
    let release: String?
    let environment: String?
    let rateLimits: RateLimits

    init(
        dsn: Dsn,
        httpClient: HTTPClient,
        servername: String?,
        release: String?,
        environment: String?,
        maxAttachmentSize: Int,
        bufferingPolicy: AsyncStream<SentryEmission>.Continuation.BufferingPolicy,
        maxInFlight: Int
    ) {
        self.dsn = dsn
        self.httpClient = httpClient
        self.servername = servername
        self.release = release
        self.environment = environment
        self.maxAttachmentSize = maxAttachmentSize
        self.rateLimits = .init(allowed: maxInFlight)
        (eventStream, cont) = AsyncStream.makeStream(bufferingPolicy: bufferingPolicy)
    }
}

public final class Sentry: Sendable {
    public enum SwiftSentryError: Error {
        case sentryTerminated
        case multipleStarts
        case dropped
        case unknownSubmissionError
        case rateLimited
        case otherServerError(status: UInt)
        case InvalidArgumentException(_ msg: String)
    }

    public enum BufferingPolicy {
        case unbounded
        case bufferingOldest(Int)
        case bufferingNewest(Int)

        func streamPolicy<T>(_ t: T.Type = T.self) -> AsyncStream<T>.Continuation.BufferingPolicy {
            switch self {
            case .unbounded: .unbounded
            case .bufferingNewest(let c): .bufferingNewest(c)
            case .bufferingOldest(let c): .bufferingOldest(c)
            }
        }
    }

    enum Running {
        case service
        case task(Task<Void, Never>)
        case none
    }

    struct SentryUUIDResponse: Codable {
        var id: String?
    }

    static let VERSION = "SentrySwift/0.1.0"
    public static let defaultMaxAttachmentSize: Int = 20_971_520
    // These ones are set by Sentry
    static let maxEnvelopeCompressedSize = 20_000_000
    static let maxEnvelopeUncompressedSize = 100_000_000
    static let maxAllAtachmentsCombined = 100_000_000
    static let maxEachAtachment = 100_000_000
    static let maxEventAndTransaction = 1_000_000
    static let maxSessionsPerEnvelope = 100
    static let maxSessionBucketPerSessions = 100

    /// Get hostname from linux C function `gethostname`. The integrated function `ProcessInfo.processInfo.hostName` does not seem to work reliable on linux
    public static func getHostname() -> String {
        var data = [CChar](repeating: 0, count: 265)
        let string: String? = data.withUnsafeMutableBufferPointer {
            guard let ptr = $0.baseAddress else {
                return nil
            }
            gethostname(ptr, 256)
            return String(cString: ptr, encoding: .utf8)
        }
        return string ?? ""
    }

    let guts: SentryGuts

    public init(
        dsn: String,
        httpClient: HTTPClient = .shared,
        servername: String? = Sentry.getHostname(),
        release: String? = nil,
        environment: String? = nil,
        maxAttachmentSize: Int = Sentry.defaultMaxAttachmentSize,
        bufferingPolicy: BufferingPolicy = .bufferingOldest(1000),
        maxInFlight: Int = 2
    ) throws {
        precondition(maxInFlight > 0)
        let dsn = try Dsn(fromString: dsn)
        self.guts = .init(
            dsn: dsn,
            httpClient: httpClient,
            servername: servername,
            release: release,
            environment: environment,
            maxAttachmentSize: maxAttachmentSize,
            bufferingPolicy: bufferingPolicy.streamPolicy(),
            maxInFlight: maxInFlight
        )
    }

    public func finish() {
        self.guts.cont.finish()
    }

    public func run() async {
        await withDiscardingTaskGroup { grp in
            for await event in guts.eventStream {
                do {
                    try await self.guts.rateLimits.allowed(event)
                } catch {
                    event.cont?.resume(throwing: error)
                    continue
                }
                grp.addTask {
                    await self.process(event)
                }
            }
        }
    }

    func process(_ event: consuming SentryEmission) async {
        let res: [Category: ContinuousClock.Instant]?
        do {
            res = try await event.process(
                client: self.guts.httpClient,
                dsn: self.guts.dsn,
                maxAttachmentSize: self.guts.maxAttachmentSize,
                sdk: nil
            )
        } catch {
            event.cont.take()?.resume(throwing: error)
            res = nil
        }
        await self.guts.rateLimits.end(new: res)
    }

    /// Queues an envelope for submission to Sentry without waiting for the result.
    ///
    /// - Important: Envelopes are only submitted while ``run()`` is running, e.g. in a separate
    ///   task or as part of a `ServiceGroup`. Envelopes sent before ``run()`` starts are buffered
    ///   according to the configured ``BufferingPolicy``; envelopes sent after ``finish()`` are
    ///   discarded.
    ///
    /// Failures, rate limiting and dropped envelopes are not reported. Use
    /// ``capture(envelope:)`` to observe the outcome.
    public func send(envelope: Envelope) {
        self.guts.cont.yield(.init(envelope: envelope, cont: nil))
    }

    /// Queues an envelope for submission to Sentry and waits until it was processed.
    ///
    /// - Important: This method requires ``run()`` to be running concurrently, e.g. in a separate
    ///   task or as part of a `ServiceGroup`. If ``run()`` is not running, this method suspends
    ///   until it is started and processes the envelope.
    ///
    /// - Returns: The event ID reported by Sentry, or `nil` if the response did not contain one.
    /// - Throws: ``SwiftSentryError/dropped`` if the buffer is full,
    ///   ``SwiftSentryError/sentryTerminated`` after ``finish()`` was called,
    ///   ``SwiftSentryError/rateLimited`` if the envelope was rate limited,
    ///   ``SwiftSentryError/otherServerError(status:)`` for other unsuccessful responses,
    ///   or any error raised while encoding or transmitting the envelope.
    @discardableResult
    public func capture(envelope: Envelope) async throws -> UUID? {
        return try await withCheckedThrowingContinuation { cont in
            switch self.guts.cont.yield(.init(envelope: envelope, cont: cont)) {
            case .dropped: cont.resume(throwing: SwiftSentryError.dropped)
            case .enqueued: break
            case .terminated: cont.resume(throwing: SwiftSentryError.sentryTerminated)
            @unknown default: cont.resume(throwing: SwiftSentryError.unknownSubmissionError)
            }
        }
    }

    /// Uploads the contents of an error log as a fatal event with the log attached, then empties the log.
    ///
    /// - Important: This method requires ``run()`` to be running concurrently, e.g. in a separate
    ///   task or as part of a `ServiceGroup`. If ``run()`` is not running, this method suspends
    ///   until it is started and processes the event.
    ///
    /// The log is only emptied after the event was submitted successfully. If the file is missing,
    /// unreadable or contains only whitespace, nothing is sent.
    ///
    /// - Returns: The event ID reported by Sentry, or `nil` if nothing was sent or the response
    ///   did not contain one.
    /// - Throws: The errors of ``capture(envelope:)``, or an error if the log could not be emptied.
    @discardableResult
    public func uploadStackTrace(path: String) async throws -> UUID? {
        let content = try? String(contentsOfFile: path, encoding: .utf8)
            .trimming(while: { $0.isWhitespace || $0.isNewline })
        guard let content, !content.isEmpty else {
            return nil
        }

        let envelope = Envelope(event: .init(
            level: .fatal,
            server_name: self.guts.servername,
            release: self.guts.release,
            environment: self.guts.environment,
            message: nil,
            exception: nil
        ), attachments: [Attachment(data: Data(content.utf8), filename: path, contentType: "text/plain")])
        let uid = try await capture(envelope: envelope)
        // empty the error log (we don't want to send events twice)
        try "".write(toFile: path, atomically: true, encoding: .utf8)
        return uid
    }
}

#if ServiceLifecycleSupport
import ServiceLifecycle

extension Sentry: Service {}
#endif
