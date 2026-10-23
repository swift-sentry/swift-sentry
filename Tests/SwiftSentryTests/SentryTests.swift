import Foundation
@testable import SwiftSentry
import Testing

struct SentryTests {
    private let dsn = "https://public@sentry.invalid/1"

    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    }

    @Test func initRejectsInvalidDsn() {
        #expect(throws: Sentry.SwiftSentryError.self) {
            try Sentry(dsn: "not a dsn")
        }
    }

    @Test func captureAfterFinishThrowsTerminated() async throws {
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

    @Test func captureWithFullBufferThrowsDropped() async throws {
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

    @Test func processEventsReturnsAfterFinish() async throws {
        let sentry = try Sentry(dsn: dsn)
        sentry.finish()
        await sentry.processEvents()
    }

    @Test func uploadStackTraceIgnoresMissingFile() async throws {
        let sentry = try Sentry(dsn: dsn)
        sentry.finish()
        #expect(try await sentry.uploadStackTrace(path: temporaryPath()) == nil)
    }

    @Test func uploadStackTraceIgnoresWhitespaceOnlyFile() async throws {
        let sentry = try Sentry(dsn: dsn)
        sentry.finish()
        let path = temporaryPath()
        try " \n\t\n ".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try await sentry.uploadStackTrace(path: path) == nil)
    }

    @Test func uploadStackTraceKeepsLogWhenSubmissionFails() async throws {
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

    @Test func bufferingPolicyMapping() {
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
