#if ServiceLifecycleSupport
import Logging
import ServiceLifecycle
@testable import SwiftSentry
import Testing

struct ServiceTests {
    /// Regression test: `run()` used to ignore graceful shutdown, so the `ServiceGroup` never returned.
    @Test(.timeLimit(.minutes(1)))
    func serviceGroupReturnsAfterGracefulShutdown() async throws {
        let sentry = try Sentry(dsn: "https://public@sentry.invalid/1")
        await rateLimitAllCategories(sentry)
        let group = ServiceGroup(services: [sentry], logger: Logger(label: "ServiceTests"))

        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask { try await group.run() }

            // Completes only once the service is processing envelopes.
            let processed = await #expect(throws: Sentry.SwiftSentryError.self) {
                try await sentry.capture(envelope: Envelope(event: Event()))
            }
            guard case .rateLimited? = processed else {
                Issue.record("Unexpected error \(String(describing: processed))")
                return
            }

            await group.triggerGracefulShutdown()
            try await tasks.next()
        }

        // Graceful shutdown finished the instance.
        let error = await #expect(throws: Sentry.SwiftSentryError.self) {
            try await sentry.capture(envelope: Envelope(event: Event()))
        }
        guard case .sentryTerminated? = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }
}
#endif
