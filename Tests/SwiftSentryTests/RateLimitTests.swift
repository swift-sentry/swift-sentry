@testable import SwiftSentry
import Testing

struct RateLimitTests {
    private let now = ContinuousClock.now

    private static func emission() -> SentryEmission {
        SentryEmission(envelope: Envelope(event: Event()), cont: nil)
    }

    @Test func parseLimitsWithCategories() {
        var limits: [Category: ContinuousClock.Instant] = [:]
        parseLimits(header: "60:error;transaction:key", into: &limits, recieveTime: now)
        #expect(limits == [
            .error: now.advanced(by: .seconds(60)),
            .transaction: now.advanced(by: .seconds(60)),
        ])
    }

    @Test func parseLimitsWithoutCategoriesAppliesToAll() {
        var limits: [Category: ContinuousClock.Instant] = [:]
        parseLimits(header: "30::organization", into: &limits, recieveTime: now)
        #expect(limits.count == Category.allCases.count)
        for category in Category.allCases {
            #expect(limits[category] == now.advanced(by: .seconds(30)))
        }
    }

    @Test func parseLimitsKeepsLongestLimit() {
        var limits: [Category: ContinuousClock.Instant] = [.error: now.advanced(by: .seconds(500))]
        parseLimits(header: "60:error;default:key, 120:default:key", into: &limits, recieveTime: now)
        #expect(limits[.error] == now.advanced(by: .seconds(500)))
        #expect(limits[.default] == now.advanced(by: .seconds(120)))
    }

    @Test func parseLimitsIgnoresInvalidEntriesAndUnknownCategories() {
        var limits: [Category: ContinuousClock.Instant] = [:]
        parseLimits(header: "abc:error, 60, 10:unknown;attachment:key,", into: &limits, recieveTime: now)
        #expect(limits == [.attachment: now.advanced(by: .seconds(10))])
    }

    @Test func emissionAllowedWithoutLimits() {
        #expect(Self.emission().allowed(with: [:]))
    }

    @Test(arguments: [Category.error, .default])
    func emissionBlockedByErrorOrDefaultLimit(_ category: Category) {
        let future = ContinuousClock.now.advanced(by: .seconds(60))
        #expect(!Self.emission().allowed(with: [category: future]))
    }

    @Test func emissionNotBlockedByUnrelatedOrExpiredLimits() {
        let future = ContinuousClock.now.advanced(by: .seconds(60))
        let past = ContinuousClock.now.advanced(by: .seconds(-60))
        #expect(Self.emission().allowed(with: [.transaction: future, .attachment: future]))
        #expect(Self.emission().allowed(with: [.error: past, .default: past]))
    }

    @Test func rateLimitsMergeKeepsLatest() async {
        let rateLimits = RateLimits(perCategory: [.error: now.advanced(by: .seconds(100))], allowed: 1)
        await rateLimits.merge(new: [
            .error: now.advanced(by: .seconds(50)),
            .transaction: now.advanced(by: .seconds(10)),
        ])
        #expect(await rateLimits.perCategory == [
            .error: now.advanced(by: .seconds(100)),
            .transaction: now.advanced(by: .seconds(10)),
        ])
    }

    @Test func rateLimitsCountsInFlightSlots() async throws {
        let rateLimits = RateLimits(allowed: 2)
        try await rateLimits.allowed(Self.emission())
        try await rateLimits.allowed(Self.emission())
        #expect(await rateLimits.allowed == 0)

        await rateLimits.end()
        #expect(await rateLimits.allowed == 1)
    }

    @Test func rateLimitsWaiterIsResumedByEnd() async throws {
        let rateLimits = RateLimits(allowed: 1)
        try await rateLimits.allowed(Self.emission())

        let waiting = Task { try await rateLimits.allowed(Self.emission()) }
        while await rateLimits.waiter == nil {
            await Task.yield()
        }
        await rateLimits.end()
        try await waiting.value

        // The slot was handed to the waiter instead of being returned to the pool.
        #expect(await rateLimits.allowed == 0)
    }

    @Test func rateLimitsRejectsLimitedEvent() async {
        let rateLimits = RateLimits(perCategory: [.error: ContinuousClock.now.advanced(by: .seconds(60))], allowed: 1)
        let error = await #expect(throws: Sentry.SwiftSentryError.self) {
            try await rateLimits.allowed(Self.emission())
        }
        guard case .rateLimited? = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
        // A rejected event does not consume an in-flight slot.
        #expect(await rateLimits.allowed == 1)
    }
}
