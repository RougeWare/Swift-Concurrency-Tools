//
//  Pool.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-06-20.
//



/// A pool of counted resources.
///
/// This pool is a bounded-concurrency limiter: up to a fixed number of operations may be using it at once.
///
/// This is different than ``Semaphore`` because it doesn't require the caller to balance every `wait()` with exactly one `signal()`, nor can it ever allow more at the same time than was specified in the initializer.
/// `Pool` removes that burden entirely. The only way `Pool` permits code to run (or makes it wait) is when that code is in a function passed to  ``borrowPermit(_:)``, which frees the permit the immediately when that functin returns.
///
/// Because the borrow and the return are guaranteed to be scoped, the number of simultaneous holders is guaranteed to never climb above the ceiling set at initialization. Freeing a permit more than once does nothing, so the permit count can only ever move within `1...maximumPermits`.
///
/// `Pool` can be used to place a cap on how many of a specific operation can run concurrently.
/// For example, to allow at most 4 downloads running using basic iteration:
///
/// ```swift
/// let downloads = Pool(maximumPermits: 4)
///
/// await withTaskGroup(of: Void.self) { group in
///     for resource in resources {
///         group.addTask {
///             await downloads.borrowPermit { // pauses before downloading if 4 permits are already checked out
///                 try? await resource.asyncDownload()
///             } // the permit is freed here, as the operation finishes
///         }
///     }
/// }
/// ```
public final class Pool: Sendable {
    
    /// The mechanism underlying `Pool`
    private let semaphore: Semaphore
    
    
    /// Creates a pool that admits at most `maximumPermits` operations at once.
    ///
    /// - Parameter maximumPermits: The maximum simultaneous permit-holders. Calling ``borrowPermit(_:)`` more than this many times at once pauses until an in-flight operation frees its permit.
    ///                             Must be at least `1`; a `Pool` that admits no one would deadlock the first time ``borrowPermit(_:)`` is called.
    public init(maximumPermits: UInt) {
        assert(maximumPermits >= 1,
               "A Pool must admit at least one operation; a maximum of 0 would immediately deadlock the first time borrowPermit() is called."
        )
        self.semaphore = Semaphore(initialPermitCount: max(1, maximumPermits))
    }
}



// MARK: - API

public extension Pool {
    
    /// Gates access to the pool so that only `maximumPermits` operations can run at once.
    ///
    /// Runs `operation` while holding one of the pool's permits, automatically freeing the permit once it returns (or throws).
    ///
    /// If every permit is already held, this suspends until one is freed, then proceeds. The longest-waiting caller sits at the front, sothis serves arrivals in the order in which they were received, so no caller can be starved.
    ///
    /// The permit's lifetime is exactly the span of `operation`: it is acquired before the first line runs and freed the moment control leaves the closure. This is what makes over-borrowing impossible: there's no handle to release (possibly more than once!), and no release to forget.
    ///
    /// - Parameter operation: The function to run only while holding a borrowed permit.
    /// - Returns: Whatever `operation` returns. The permit is freed as this returns.
    /// - Throws: Whatever `operation` throws. The permit is freed as this throws.
    func borrowPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await semaphore.withPermit(operation)
    }
}
