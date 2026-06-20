//
//  Semaphore Tests.swift
//  ConcurrencyTools
//
//  Created by Ky directing Claude Opus 4.8 on 2026-06-20.
//

import Testing
import ConcurrencyTools



/// Exercises the stable public contract of ``Semaphore``: the counting
/// behaviour of `init`/`wait()`/`signal()`, and the acquire-run-release
/// guarantee of `withPermit(_:)`.
///
/// The semaphore's *cancellable* surface is deliberately absent from this
/// suite. There is no public entry point through which a cancellation can be
/// observed, so it cannot be exercised without reaching past the public API —
/// and per the project's testing discipline, that gap is design feedback to be
/// resolved at the source, not worked around here.
///
/// Strict FIFO ordering is likewise left unasserted. Establishing a
/// deterministic park order requires a coordination primitive the public
/// surface does not yet expose; a timing-based approximation would be flaky
/// rather than authoritative, so it is intentionally omitted.
@Suite("Semaphore")
struct SemaphoreTests {

    // MARK: - Permit accounting

    /// A semaphore created with permits in hand must admit that many callers
    /// without any matching `signal()`. This guards the fast path of `wait()`,
    /// where a permit is consumed synchronously and the caller never parks.
    @Test("Initial permits are available without a signal",
          .timeLimit(.minutes(1)))
    func initialPermitsAreImmediatelyAvailable() async {
        let semaphore = Semaphore(initialPermitCount: 3)
        await semaphore.wait()
        await semaphore.wait()
        await semaphore.wait()
        // A fourth wait would park by design; the contract under test ends here.
    }

    /// With no permits available, a caller must park and then resume once a
    /// permit is released. This holds under either ordering: if the waiter
    /// parks first, `signal()` hands the permit directly to it; if `signal()`
    /// lands first, it banks a permit that the subsequent `wait()` consumes.
    /// A regression in either direction strands the waiter, which the time
    /// limit surfaces as a failure.
    @Test("A parked waiter resumes when a permit is signaled",
          .timeLimit(.minutes(1)))
    func parkedWaiterResumesOnSignal() async {
        let semaphore = Semaphore(initialPermitCount: 0)
        let waiter = Task { await semaphore.wait() }
        semaphore.signal()
        await waiter.value
    }

    /// A `signal()` arriving with no one waiting must not be discarded; it
    /// raises the permit count so the next `wait()` returns without parking.
    /// This guards the branch of `signal()` taken when the wait queue is empty.
    @Test("signal() with no waiter banks a permit for the next wait()",
          .timeLimit(.minutes(1)))
    func signalWithoutWaiterBanksAPermit() async {
        let semaphore = Semaphore(initialPermitCount: 0)
        semaphore.signal()
        await semaphore.wait()
    }

    /// The defining guarantee of a counting semaphore: at no instant may more
    /// than `initialPermitCount` callers hold a permit at once. Each task
    /// records its entry and exit against a shared tracker, and `Task.yield()`
    /// widens the held window so any breach has room to be observed. The peak
    /// occupancy is then asserted against the permit ceiling.
    @Test("Never admits more holders than its permit count",
          .timeLimit(.minutes(1)),
          arguments: [1, 2, 4])
    func boundsConcurrentHolders(limit: Int) async {
        let semaphore = Semaphore(initialPermitCount: UInt(limit))
        let tracker = OccupancyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    await semaphore.withPermit {
                        await tracker.enter()
                        await Task.yield()
                        await tracker.leave()
                    }
                }
            }
        }

        let observedPeak = await tracker.peak
        #expect(observedPeak <= limit,
                "Observed \(observedPeak) concurrent holders against a ceiling of \(limit)")
    }

    // MARK: - withPermit

    /// `withPermit(_:)` is a convenience over `wait()`/`signal()`, so it must
    /// forward whatever its operation produces back to the caller unchanged.
    @Test("withPermit returns the operation's value",
          .timeLimit(.minutes(1)))
    func withPermitForwardsReturnValue() async {
        let semaphore = Semaphore(initialPermitCount: 1)
        let answer = await semaphore.withPermit { 42 }
        #expect(answer == 42)
    }

    /// The reason `withPermit(_:)` exists is to make the releasing `signal()`
    /// unforgettable — including when the operation fails. After a throwing
    /// operation the permit must have been returned; otherwise this
    /// single-permit semaphore would never admit the second caller, and the
    /// time limit would fail the test.
    @Test("withPermit releases its permit even when the operation throws",
          .timeLimit(.minutes(1)))
    func withPermitReleasesPermitOnThrow() async {
        struct Boom: Error {}
        let semaphore = Semaphore(initialPermitCount: 1)

        try? await semaphore.withPermit { throw Boom() }

        await semaphore.withPermit { }
    }

    /// A failure inside the operation belongs to the caller, not the
    /// semaphore. `withPermit(_:)` must rethrow it verbatim rather than
    /// swallowing or substituting it.
    @Test("withPermit rethrows the operation's error to the caller",
          .timeLimit(.minutes(1)))
    func withPermitRethrowsOperationError() async {
        struct Boom: Error, Equatable {}
        let semaphore = Semaphore(initialPermitCount: 1)

        do {
            try await semaphore.withPermit { throw Boom() }
            Issue.record("Expected Boom to be rethrown, but the call returned normally")
        }
        catch is Boom {
            // Reaching here is the assertion.
        }
        catch {
            Issue.record("Expected Boom but caught \(error)")
        }
    }
}



/// A shared, isolation-safe occupancy meter for ``SemaphoreTests``.
///
/// It exists so the concurrency-bound test can observe how many tasks were
/// inside a permit simultaneously without itself introducing a data race.
/// Actor isolation serialises the `enter`/`leave` bookkeeping, and the highest
/// concurrent occupancy is retained in ``peak`` for the test to assert against.
private actor OccupancyTracker {

    /// The greatest number of simultaneous holders observed so far — the value
    /// the bounding test compares against the permit ceiling.
    private(set) var peak = 0

    /// The number of holders currently inside a permit.
    private var current = 0

    /// Record a caller entering its permit, advancing the high-water mark.
    func enter() {
        current += 1
        peak = max(peak, current)
    }

    /// Record a caller leaving its permit.
    func leave() {
        current -= 1
    }
}
