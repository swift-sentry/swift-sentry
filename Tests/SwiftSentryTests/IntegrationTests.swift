import Foundation
@testable import SwiftSentry
import Testing

/// DSN of the server used by ``IntegrationTests``, or `nil` if they are disabled.
private let integrationDsn: String? = ProcessInfo.processInfo.environment["SENTRY_INTEGRATION_DSN"]
    .flatMap { $0.isEmpty ? nil : $0 }

/// Sends envelopes to a real Sentry-compatible server.
///
/// Disabled unless `SENTRY_INTEGRATION_DSN` is set. Start a local server with
/// `docker compose up -d --wait` and pass the DSN printed by its bootstrap step.
/// A dedicated variable is used instead of `SENTRY_DSN` so test events are never
/// sent to a project that happens to be configured in the environment.
@Suite(
    .enabled(if: integrationDsn != nil, "Set SENTRY_INTEGRATION_DSN to run integration tests"),
    .timeLimit(.minutes(1))
)
struct IntegrationTests {
    /// Runs `body` with a `Sentry` instance that is processing events against `dsn`.
    private func withSentry<T>(
        dsn: String? = integrationDsn,
        _ body: (Sentry) async throws -> T
    ) async throws -> T {
        let sentry = try Sentry(
            dsn: #require(dsn),
            release: "swift-sentry-integration-tests",
            environment: "test"
        )
        let processing = Task { await sentry.processEvents() }
        defer { sentry.finish() }
        let result = try await body(sentry)
        sentry.finish()
        await processing.value
        return result
    }

    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    }

    @Test
    func `capture returns event id`() async throws {
        let eventId = UUID()
        let returned = try await withSentry { sentry in
            try await sentry.capture(envelope: Envelope(event: Event(
                event_id: eventId,
                level: .error,
                message: .raw(message: "integration test: \(#function)")
            )))
        }
        #expect(returned == eventId)
    }

    @Test
    func `capture with exception and tags`() async throws {
        let eventId = UUID()
        let frame = Frame(
            filename: #fileID,
            function: #function,
            raw_function: nil,
            lineno: #line,
            colno: nil,
            abs_path: #filePath,
            instruction_addr: nil
        )
        let event = Event(
            event_id: eventId,
            level: .warning,
            logger: "IntegrationTests",
            tags: ["suite": "integration"],
            message: .raw(message: "integration test: \(#function)"),
            exception: Exceptions(values: [ExceptionDataBag(
                type: "IntegrationTestError",
                value: "something went wrong",
                stacktrace: Stacktrace(frames: [frame])
            )]),
            breadcrumbs: Breadcrumbs(values: [Breadcrumb(message: "before failure", level: .info)])
        )
        let returned = try await withSentry { sentry in
            try await sentry.capture(envelope: Envelope(event: event))
        }
        #expect(returned == eventId)
    }

    @Test
    func `capture with attachments`() async throws {
        let eventId = UUID()
        let envelope = Envelope(
            event: Event(event_id: eventId, level: .error, message: .raw(message: "integration test: \(#function)")),
            attachments: [
                Attachment(data: Data("plain text attachment".utf8), filename: "log.txt", contentType: "text/plain"),
                Attachment(data: [0x00, 0xff, 0x10, 0x0a], filename: "blob.bin"),
            ]
        )
        let returned = try await withSentry { sentry in
            try await sentry.capture(envelope: envelope)
        }
        #expect(returned == eventId)
    }

    @Test
    func `concurrent captures all succeed`() async throws {
        let eventIds = (0..<10).map { _ in UUID() }
        let returned = try await withSentry { sentry in
            try await withThrowingTaskGroup(of: UUID?.self) { group in
                for eventId in eventIds {
                    group.addTask {
                        try await sentry.capture(envelope: Envelope(event: Event(
                            event_id: eventId,
                            level: .info,
                            message: .raw(message: "integration test: \(#function)")
                        )))
                    }
                }
                return try await group.reduce(into: Set<UUID?>()) { $0.insert($1) }
            }
        }
        #expect(returned == Set(eventIds))
    }

    @Test
    func `upload stack trace submits and empties log`() async throws {
        let path = temporaryPath()
        try "Fatal error: integration test\nframe 0\nframe 1".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let returned = try await withSentry { sentry in
            try await sentry.uploadStackTrace(path: path)
        }
        #expect(returned != nil)
        #expect(try String(contentsOfFile: path, encoding: .utf8).isEmpty)
    }

    @Test
    func `unknown public key is rejected`() async throws {
        let dsn = try #require(integrationDsn.flatMap(URLComponents.init(string:)))
        var invalid = dsn
        invalid.user = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")

        let error = try await withSentry(dsn: invalid.string) { sentry in
            await #expect(throws: Sentry.SwiftSentryError.self) {
                try await sentry.capture(envelope: Envelope(event: Event(message: .raw(message: "must be rejected"))))
            }
        }
        guard case .otherServerError(let status)? = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
        #expect((400..<500).contains(status))
    }
}
