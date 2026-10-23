import AsyncHTTPClient
import DequeModule
import Foundation
import NIO
import NIOFoundationCompat
import NIOHTTP1
import Synchronization

func parseLimits(header: String, into limits: inout [Category: ContinuousClock.Instant], recieveTime: ContinuousClock.Instant) {
    for limit in header.split(separator: ",", omittingEmptySubsequences: false).map({ $0.trimming(while: { $0.isWhitespace }) }) {
        let component = limit.split(separator: ":", omittingEmptySubsequences: false)
        guard component.count >= 2, let retryAfter = Double(component[0]) else {
            continue
        }
        let categoriesComp = component[1]
        guard !categoriesComp.isEmpty else {
            for cat in Category.allCases {
                limits[cat] = max(recieveTime.advanced(by: .seconds(retryAfter)), limits[cat, default: recieveTime])
            }
            continue
        }
        for cat in categoriesComp.split(separator: ";", omittingEmptySubsequences: false).compactMap(Category.init) {
            limits[cat] = max(recieveTime.advanced(by: .seconds(retryAfter)), limits[cat, default: recieveTime])
        }
    }
}

struct SentryEmission {
    let envelope: Envelope

    func process(
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
        switch response.status {
        case .tooManyRequests where rateLimits.isEmpty:
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
            break
        // let dec = JSONDecoder()
        // let bytes = try await response.body.collect(upTo: 50)
        // let resp = try dec.decode(Sentry.SentryUUIDResponse.self, from: bytes)
        // let uuid = resp.id.flatMap { UUID(fromHexadecimalEncodedString: $0) }
        default:
            break
        }
        return rateLimits
    }

    func allowed(with limits: [Category: ContinuousClock.Instant]) -> Bool {
        if let ev = envelope.event {
            switch ev.cause.type {
            case .event:
                guard limits[.error, default: .now] <= .now, limits[.default, default: .now] <= .now else {
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
        waiters: Deque<UnsafeContinuation<Void, Never>> = [],
        allowed: Int
    ) {
        self.perCategory = perCategory
        self.waiters = waiters
        self.allowed = allowed
    }

    var perCategory: [Category: ContinuousClock.Instant] = [:]
    var waiters: Deque<UnsafeContinuation<Void, Never>> = []
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
        await withUnsafeContinuation {
            waiters.append($0)
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
        if let w = waiters.popFirst() {
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
    enum SwiftSentryError: Error {
        case rateLimited
        case otherFailure(HTTPResponseStatus)
        // case CantEncodeEvent
        // case CantCreateRequest
        case NoResponseBody(status: UInt)
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

    // public func shutdown() async throws {
    //     try await self.guts.httpClient.shutdown()
    // }

    public func run() async throws {
        await withDiscardingTaskGroup { grp in
            for await event in guts.eventStream {
                grp.addTask {
                    await self.process(event)
                }
            }
        }
    }

    func process(_ event: SentryEmission) async {
        do {
            try await self.guts.rateLimits.allowed(event)
        } catch {
            return
        }
        let res: [Category: ContinuousClock.Instant]?
        do {
            res = try await event.process(
                client: self.guts.httpClient,
                dsn: self.guts.dsn,
                maxAttachmentSize: self.guts.maxAttachmentSize,
                sdk: nil
            )
        } catch {
            res = nil
        }
        await self.guts.rateLimits.end(new: res)
    }

    // @discardableResult
    // public func capture(envelope: Envelope) async throws -> UUID? {
    //     try await withCheckedThrowingContinuation { cont in
    //         self.guts.cont.yield(.init(envelope: envelope, cont: cont))
    //     }
    // }

    public func send(envelope: Envelope) {
        self.guts.cont.yield(.init(envelope: envelope))
    }

    public func uploadStackTrace(path: String) throws {
        let content = try? String(contentsOfFile: path, encoding: .utf8)
            .trimming(while: { $0.isWhitespace || $0.isNewline })
        guard let content, !content.isEmpty else {
            return
        }

        // empty the error log (we don't want to send events twice)
        try "".write(toFile: path, atomically: true, encoding: .utf8)

        let envelope = Envelope(event: .init(
            level: .fatal,
            server_name: self.guts.servername,
            release: self.guts.release,
            environment: self.guts.environment,
            message: nil,
            exception: nil
        ), attachments: [Attachment(data: Data(content.utf8), filename: path, contentType: "text/plain")])
        send(envelope: envelope)
    }
}
