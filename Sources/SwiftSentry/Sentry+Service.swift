#if ServiceLifecycleSupport
public import ServiceLifecycle

extension Sentry: Service {
    /// Runs ``processEvents()`` and calls ``finish()`` on graceful shutdown, so queued envelopes
    /// are submitted before the service returns.
    ///
    /// Place the `Sentry` instance first in the `ServiceGroup` so it shuts down after the services
    /// that log through it.
    public func run() async throws {
        await withGracefulShutdownHandler {
            await self.processEvents()
        } onGracefulShutdown: {
            self.finish()
        }
    }
}
#endif
