//
//  Semaphore.swift
//  ConcurrencyTools
//
//  Created by Ky on 2025-05-08.
//

import Foundation



/// A modern API for semaphores.
///
/// This file provides a modern (structured concurrency) API for counting semaphores, without using GCD at all.
///
/// Call ``wait()`` to pause there and wait for something else to call ``signal()``.
///
/// You can provide an initial permit count to make it so that ``wait()`` doesn't actually wait until it's run out of permits.
///
/// Calling ``signal()`` when there's nothing waiting does nothing.
/// Calling ``wait()`` when nothing will signal it later will result in that task permanently freezing..
///
/// Learn more about counting semaphores here: https://en.wikipedia.org/wiki/Semaphore_(programming)
///
///
///
/// ### Example 1
///
/// Protect a critical section by `await`ing ``wait()``:
///
/// ```swift
/// actor Client {
///     private let semaphore = Semaphore(initialPermitCount: 1)
///
///     func request() async throws -> Data {
///         await semaphore.wait() // Only waits if at least 1 other thing already called this, but hasn't yet been `signal`ed.
///         defer { semaphore.signal() }
///         return try await URLSession.shared.data(for: /*...*/).0
///     }
/// }
/// ```
///
///
///
/// ### Example 2
///
/// Bounded concurrency: allow _n_ things at once. Before any new things can start, one old one must be signaled:
///
/// ```swift
/// // Allow 4 downloads at the same time
/// let downloadSemaphore = Semaphore(initialPermitCount: 4)
///
/// for resource in resources {
///     await downloadSemaphore.wait()
///     resource.download { result in
///         downloadSemaphore.signal()
///         // ...
///     }
/// }
/// ```
///
///
///
/// - Note: Unlike ``DispatchSemaphore``, `Semaphore` never blocks an actual OS thread.
///         Instead, callers of ``wait()`` are suspended by the Swift concurrency runtime and resumed cooperatively.
///         This makes `Semaphore` safe to run under heavy task load, where ``DispatchSemaphore`` isn't.
///
///- Note: This intentionally ignores cooperative cancelling. The ``wait()`` and ``signal()`` functions always work the same regardless of whether the current task is cancelled.
///        This follows the principal of least surprise: you wouldn't expect just using a semaphore to be the thing that prematurely exits your current task, and you might want to use a semaphore to handle the catching of a ``CancellationError``, so this leaves cooperative cancelling up to the caller to do more explicitly elsewhere.
///
/// - Attention: To prevent a complete deadlock, deallocating this semaphore also signals everyone `wait`ing on it, so make sure you keep a reference to it as long as you want things waiting
public final class Semaphore: @unchecked Sendable {
    
    /// Guarantees that access to the state of this class is mutually exclusive across concurrency contexts, just like an `actor`, but without having to `await` anything that isn't explicitly marked `await`.
    ///
    /// This allows us to write `singal()` without writing `await signal()`.
    ///
    /// `NSLock` is a thin wrapper around the POSIX (not GCD) call `pthread_mutex_*` functions. That only uses kernelspace when there's actual contention, which keeps the uncontended `wait()`/`signal()` path cheap.
    private let fakeActor = NSLock()
    
    /// How many permits are currently available.
    ///
    /// When this is `0`, callers join ``waiters`` instead of returning.
    private var permits: UInt
    
    /// FIFO queue of waiting callers, each represented as the continuation that resumes it.
    ///
    /// The longest-waiting caller sits at the front, so ``signal()`` serves arrivals in the order in which they were received, so no caller can be starved.
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    
    /// Creates a semaphore, optionally with the given starting number of permits.
    ///
    /// - Parameter initialPermitCount: The initial number of permits available in this semaphore. The two most common choices are `0` (every caller waits for the first signal) and `1` (the semaphore acts as a mutual-exclusion lock).
    ///                                 Defaults to `0`.
    public init(initialPermitCount: UInt = 0) {
        self.permits = UInt(initialPermitCount)
    }
    
    
    deinit {
        // Resume all waiters so they don't wait forever on a deallocated semaphore
        for waiter in waiters {
            waiter.resume()
        }
    }
}



// MARK: - Public API

public extension Semaphore {
    
    /// Suspends the caller until a permit becomes available.
    ///
    /// When this semaphore is initialized with 0 permits (the default), then this immediately suspents the caller until ``signal()`` is called from elsewhere.
    ///
    /// If a permit is already available, this borrows it and continues immediately.
    /// Otherwise, the caller joins the FIFO wait queue and resumes when a future ``signal()`` gives it a freed permit.
    ///
    /// This call is **not cancellable**.
    /// A cancelled task that is waiting keeps waiting, and may handle cancellation once the wait returns.
    /// See the type docuemtation's notes for more.
    func wait() async {
        await withCheckedContinuation { continuation in
            fakeActor.lock()
            
            guard 0 >= permits else {
                permits -= 1
                fakeActor.unlock()
                continuation.resume()
                return
            }
            
            waiters.append(continuation)
            fakeActor.unlock()
        }
    }
    
    
    /// Releases one permit, resuming the next waiting caller if any.
    ///
    /// When this semaphore is initialized with 0 permits (the default), then this immediately resumes the only waiter.
    ///
    /// If there are existing waiters, this resumes the one which has been waiting the longest.
    /// Else, this increases the permit count grows by one, so the next ``wait()`` returns without suspending.
    ///
    /// This call is synchronous, so it's safe to use from any context —
    /// including `defer` blocks, deinitializers, and non-`async` functions.
    func signal() {
        fakeActor.lock()
        
        if waiters.isEmpty {
            permits += 1
            fakeActor.unlock()
        }
        else {
            let next = waiters.removeFirst()
            fakeActor.unlock()
            next.resume()
        }
    }
    
    
    /// Acquires a permit, runs the given operation, then frees the permit on the way out.
    ///
    /// The permit is freed even if the operation throws an error.
    ///
    /// Equivalent to:
    /// ```swift
    /// await semaphore.wait()
    /// defer { semaphore.signal() }
    /// return try await operation()
    /// ```
    /// but without needing to balance `wait()`/`signal()` calls:
    /// ```swift
    /// await semaphore.withPermit { // implcit wait() call
    ///     operation()
    /// } // implicit signal() call
    /// ```
    ///
    /// - Parameter operation: The work to run when the semaphore has a permit to run it.
    /// - Returns: Whatever `operation` returns. The permit is freed as this returns.
    /// - Throws: Whatever `operation` throws. The permit is freed as this throws.
    func withPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        await wait()
        defer { signal() }
        return try await operation()
    }
}
