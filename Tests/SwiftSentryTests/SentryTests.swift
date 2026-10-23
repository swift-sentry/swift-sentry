import Foundation
@testable import SwiftSentry
import Testing

/// Rate limits every category, so processed envelopes are rejected with `rateLimited` without any
/// network access.
func rateLimitAllCategories(_ sentry: Sentry) async {
    let until = ContinuousClock.now.advanced(by: .seconds(3600))
    await sentry.guts.rateLimits.merge(new: Dictionary(uniqueKeysWithValues: Category.allCases.map { ($0, until) }))
}

struct SentryTests {
    private let dsn = "https://public@sentry.invalid/1"

    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    }

    private static func failure(_ result: Result<UUID?, any Error>?) -> Sentry.SwiftSentryError? {
        guard case .failure(let error)? = result else {
            return nil
        }
        return error as? Sentry.SwiftSentryError
    }

    @Test
    func initRejectsInvalidDsn() {
        #expect(throws: Sentry.SwiftSentryError.self) {
            try Sentry(dsn: "not a dsn")
        }
    }

    @Test
    func captureAfterFinishThrowsTerminated() async throws {
        let sentry = try Sentry(dsn: dsn)
        sentry.finish()
        let error = await #expect(throws: Sentry.SwiftSentryError.self) {
            try await sentry.capture(envelope: Envelope(event: Event()))
        }
        guard case .sentryTerminated? = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }

    @Test
    func captureWithFullBufferThrowsDropped() async throws {
        let sentry = try Sentry(dsn: dsn, bufferingPolicy: .bufferingOldest(1))
        sentry.send(envelope: Envelope(event: Event()))
        let error = await #expect(throws: Sentry.SwiftSentryError.self) {
            try await sentry.capture(envelope: Envelope(event: Event()))
        }
        guard case .dropped? = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }

    /// With `bufferingNewest`, a full buffer evicts the *older* envelope. Its capture must fail with
    /// `dropped`, while the newer one stays queued and is processed later. Regression test: the
    /// newer capture used to be failed instead, leaking the evicted continuation and resuming the
    /// newer one a second time once it was processed.
    @Test(.timeLimit(.minutes(1)))
    func captureEvictedByBufferingNewestThrowsDropped() async throws {
        let sentry = try Sentry(dsn: dsn, bufferingPolicy: .bufferingNewest(1))
        await rateLimitAllCategories(sentry)
        await withTaskGroup(of: Result<UUID?, any Error>.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        return try await .success(sentry.capture(envelope: Envelope(event: Event())))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            // Nothing is processed yet, so the only capture that can finish is the evicted one.
            let evicted = await group.next()
            guard case .dropped? = Self.failure(evicted) else {
                Issue.record("Expected the evicted capture to be dropped, got \(String(describing: evicted))")
                return
            }

            sentry.finish()
            await sentry.processEvents()

            // The kept capture reached processing, where the rate limit rejects it.
            let kept = await group.next()
            guard case .rateLimited? = Self.failure(kept) else {
                Issue.record("Expected the kept capture to be processed, got \(String(describing: kept))")
                return
            }
        }
    }

    @Test
    func processEventsReturnsAfterFinish() async throws {
        let sentry = try Sentry(dsn: dsn)
        sentry.finish()
        await sentry.processEvents()
    }

    @Test
    func uploadStackTraceIgnoresMissingFile() async throws {
        let sentry = try Sentry(dsn: dsn)
        sentry.finish()
        #expect(try await sentry.uploadStackTrace(path: temporaryPath()) == nil)
    }

    @Test
    func uploadStackTraceIgnoresWhitespaceOnlyFile() async throws {
        let sentry = try Sentry(dsn: dsn)
        sentry.finish()
        let path = temporaryPath()
        try " \n\t\n ".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try await sentry.uploadStackTrace(path: path) == nil)
    }

    @Test
    func uploadStackTraceKeepsLogWhenSubmissionFails() async throws {
        let sentry = try Sentry(dsn: dsn)
        sentry.finish()
        let path = temporaryPath()
        try "fatal error\nstack".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let error = await #expect(throws: Sentry.SwiftSentryError.self) {
            try await sentry.uploadStackTrace(path: path)
        }
        guard case .sentryTerminated? = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "fatal error\nstack")
    }

    @Test
    func bufferingPolicyMapping() {
        func describe(_ policy: AsyncStream<Int>.Continuation.BufferingPolicy) -> String {
            switch policy {
            case .unbounded: "unbounded"
            case .bufferingOldest(let n): "oldest(\(n))"
            case .bufferingNewest(let n): "newest(\(n))"
            @unknown default: "unknown"
            }
        }
        #expect(describe(Sentry.BufferingPolicy.unbounded.streamPolicy(Int.self)) == "unbounded")
        #expect(describe(Sentry.BufferingPolicy.bufferingOldest(3).streamPolicy(Int.self)) == "oldest(3)")
        #expect(describe(Sentry.BufferingPolicy.bufferingNewest(4).streamPolicy(Int.self)) == "newest(4)")
    }
}
