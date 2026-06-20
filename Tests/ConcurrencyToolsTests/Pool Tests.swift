//
//  Pool Tests.swift
//  ConcurrencyTools
//
//  Created by Ky directing Claude Opus 4.8 on 2026-06-20.
//

import Testing
import ConcurrencyTools



/// Exercises the public contract of ``Pool``: that `borrowPermit(_:)` runs work
/// under a permit, never admits more concurrent holders than the ceiling set at
/// creation, returns and rethrows transparently, and always hands the permit
/// back so the pool keeps flowing.
///
/// The "by construction" ceiling claim is the one that matters most, so it is
/// proven directly — by observing peak concurrency under contention rather than
/// by trusting the implementation.
@Suite("Pool")
struct PoolTests {

    // MARK: - The ceiling

    /// The defining guarantee: no matter how many borrowers pile up, the number
    /// holding a permit at the same instant never exceeds the pool's maximum.
    /// Each borrower records its entry and exit against a shared tracker, and
    /// `Task.yield()` widens the held window so any breach has room to surface.
    /// The observed peak is asserted against the ceiling.
    @Test("Never admits more concurrent holders than its maximum",
          .timeLimit(.minutes(1)),
          arguments: [1, 2, 4])
    func boundsConcurrentHolders(maximum: Int) async {
        let pool = Pool(maximumPermits: UInt(maximum))
        let tracker = OccupancyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    await pool.borrowPermit {
                        await tracker.enter()
                        await Task.yield()
                        await tracker.leave()
                    }
                }
            }
        }

        let observedPeak = await tracker.peak
        #expect(observedPeak <= maximum,
                "Observed \(observedPeak) concurrent holders against a ceiling of \(maximum)")
    }

    /// A pool whose permits are all free must let the work run straight through
    /// without suspending. With a ceiling of one and nothing else contending,
    /// a single borrow should complete on its own; a regression that failed to
    /// grant the first permit would hang, which the time limit catches.
    @Test("An uncontended borrow runs without waiting",
          .timeLimit(.minutes(1)))
    func uncontendedBorrowProceeds() async {
        let pool = Pool(maximumPermits: 1)
        var ran = false
        await pool.borrowPermit { ran = true }
        #expect(ran)
    }

    /// Permits must be reusable: once a borrow returns, the permit it held is
    /// available again. A single-permit pool driven through several sequential
    /// borrows proves the permit is genuinely handed back each time rather than
    /// consumed once and lost.
    @Test("Permits are returned and reused across sequential borrows",
          .timeLimit(.minutes(1)))
    func permitsAreReusedSequentially() async {
        let pool = Pool(maximumPermits: 1)
        var count = 0
        for _ in 0 ..< 5 {
            await pool.borrowPermit { count += 1 }
        }
        #expect(count == 5)
    }

    // MARK: - Pass-through behaviour

    /// `borrowPermit(_:)` is a wrapper around the caller's work, so it must
    /// return whatever that work produces, unchanged.
    @Test("Returns the operation's value to the caller",
          .timeLimit(.minutes(1)))
    func forwardsReturnValue() async {
        let pool = Pool(maximumPermits: 2)
        let answer = await pool.borrowPermit { 6 * 7 }
        #expect(answer == 42)
    }

    /// A permit must come back even when the borrowed work throws — otherwise a
    /// failing operation would slowly drain the pool. After a throwing borrow,
    /// a single-permit pool must still admit the next borrower; if the permit
    /// had leaked, this second borrow would wait forever.
    @Test("Returns the permit even when the operation throws",
          .timeLimit(.minutes(1)))
    func returnsPermitWhenOperationThrows() async {
        struct Boom: Error {}
        let pool = Pool(maximumPermits: 1)

        try? await pool.borrowPermit { throw Boom() }

        await pool.borrowPermit { }
    }

    /// A failure inside the borrowed work belongs to the caller. `borrowPermit`
    /// must rethrow it as-is rather than swallowing or substituting it.
    @Test("Rethrows the operation's error to the caller",
          .timeLimit(.minutes(1)))
    func rethrowsOperationError() async {
        struct Boom: Error, Equatable {}
        let pool = Pool(maximumPermits: 1)

        do {
            try await pool.borrowPermit { throw Boom() }
            Issue.record("Expected Boom to be rethrown, but the call returned normally")
        }
        catch is Boom {
            // Reaching here is the assertion.
        }
        catch {
            Issue.record("Expected Boom but caught \(error)")
        }
    }

    // MARK: - Shared-handle semantics

    /// A `Pool` is a value type over shared storage, so a copy must throttle
    /// against the *same* ceiling rather than spawning an independent limit.
    /// Borrowing through both the original and its copy must never exceed the
    /// single shared maximum.
    @Test("A copied pool shares one ceiling rather than creating a second",
          .timeLimit(.minutes(1)))
    func copiesShareOneCeiling() async {
        let original = Pool(maximumPermits: 2)
        let copy = original
        let tracker = OccupancyTracker()

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 50 {
                let pool = index.isMultiple(of: 2) ? original : copy
                group.addTask {
                    await pool.borrowPermit {
                        await tracker.enter()
                        await Task.yield()
                        await tracker.leave()
                    }
                }
            }
        }

        let observedPeak = await tracker.peak
        #expect(observedPeak <= 2,
                "Two handles to one pool admitted \(observedPeak) holders; expected at most 2")
    }
}



/// A shared, isolation-safe occupancy meter for ``PoolTests``.
///
/// It lets the concurrency-bound tests observe how many borrowers held a permit
/// at once without introducing a data race of their own. Actor isolation
/// serialises the `enter`/`leave` bookkeeping, and the highest concurrent
/// occupancy is retained in ``peak`` for the tests to assert against.
private actor OccupancyTracker {

    /// The greatest number of simultaneous holders observed so far — the value
    /// the bounding tests compare against the ceiling.
    private(set) var peak = 0

    /// The number of borrowers currently holding a permit.
    private var current = 0

    /// Record a borrower entering its permit, advancing the high-water mark.
    func enter() {
        current += 1
        peak = max(peak, current)
    }

    /// Record a borrower leaving its permit.
    func leave() {
        current -= 1
    }
}
