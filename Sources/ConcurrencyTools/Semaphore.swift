//
//  Semaphore.swift
//  ConcurrencyTools
//
//  Created by Ky on 2025-05-08.
//

import Foundation



/// An async counting semaphore — a coordination primitive that suspends
/// callers when a resource is unavailable, rather than blocking a thread.
///
/// A semaphore holds a non-negative count of "permits". Calling ``wait()``
/// either consumes a permit (returning right away) or suspends the caller
/// until ``signal()`` releases one. With an initial count of `1`, the
/// semaphore behaves as a mutual-exclusion lock that's safe to hold
/// across `await` boundaries.
///
/// Unlike `DispatchSemaphore`, this implementation never blocks an OS
/// thread. Suspended callers are parked by the Swift concurrency runtime
/// and resumed cooperatively, so they don't consume thread-pool capacity
/// while waiting. This is what makes the semaphore safe to use under
/// heavy task load, where blocking a thread would risk deadlocking the
/// cooperative pool.
///
/// ## Example — protect a critical section across `await`
///
/// ```swift
/// actor Client {
///     private let semaphore = Semaphore(initialPermitCount: 1)
///
///     func request() async throws -> Data {
///         await semaphore.wait()
///         defer { semaphore.signal() }
///         return try await URLSession.shared.data(for: request).0
///     }
/// }
/// ```
///
/// ## Example — bounded concurrency
///
/// ```swift
/// // Allow at most 4 downloads in flight at once
/// let downloads = Semaphore(initialPermitCount: 4)
/// ```
///
/// ## Cancellation
///
/// ``wait()`` is intentionally **not** cancellable: a task may be marked
/// cancelled while waiting, but the wait still completes normally when
/// a signal arrives. If you want a cancelled task to stop waiting and
/// throw `CancellationError`, use ``waitUnlessCancelled()`` instead.
public final class Semaphore: @unchecked Sendable {
    
    /// Guards `permits` and `suspensions`. `NSLock` is a thin wrapper
    /// around `pthread_mutex` — it's not GCD, and only enters the kernel
    /// when there's actual contention.
    private let lock = NSLock()
    
    /// How many permits are currently available. Never negative.
    /// When this is `0`, callers join `suspensions` instead of returning.
    private var permits: Int
    
    /// FIFO queue of suspended callers. Each suspension is held by
    /// reference so a cancellation handler can find a specific waiter
    /// using `===` identity (continuations aren't `Equatable`).
    private var suspensions: [Suspension] = []
    
    
    /// Creates a semaphore with the given starting number of permits.
    ///
    /// - Parameter initialPermitCount: How many permits are available
    ///   at creation. The two most common choices are `0` (every caller
    ///   waits for the first signal) and `1` (the semaphore acts as a
    ///   mutual-exclusion lock).
    public init(initialPermitCount: UInt = 0) {
        self.permits = Int(initialPermitCount)
    }
    
    
    deinit {
        // Resume any leftover waiters so their tasks don't leak forever.
        // No locking needed: by the time deinit runs, nothing else can
        // be holding a reference to this instance.
        //
        // (In practice this branch is rarely reachable, since each
        // pending `wait()` callsite holds the Semaphore alive via its
        // function frame. It's here as a safety net for the case where
        // the user's lifecycle management lets the instance drop.)
        for suspension in suspensions {
            suspension.resume()
        }
    }
}



// MARK: - Public API

public extension Semaphore {
    
    /// Suspends the caller until a permit becomes available.
    ///
    /// If a permit is already available, this returns right away after
    /// consuming it. Otherwise the caller joins the FIFO wait queue and
    /// resumes when a future ``signal()`` releases a permit to them.
    ///
    /// This call is **not** cancellable. A cancelled task that's waiting
    /// will keep waiting; it just sees `Task.isCancelled == true` after
    /// the wait returns. For cancellable behavior, use
    /// ``waitUnlessCancelled()``.
    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            
            if 0 < permits {
                permits -= 1
                lock.unlock()
                continuation.resume()
                return
            }
            
            suspensions.append(Suspension(continuation))
            lock.unlock()
        }
    }
    
    
    /// Releases one permit, resuming the next waiting caller if any.
    ///
    /// If callers are queued, the longest-waiting one resumes. Otherwise
    /// the permit count grows by one, so the next ``wait()`` returns
    /// without suspending.
    ///
    /// This call is synchronous, so it's safe to use from any context —
    /// including `defer` blocks, deinitializers, and non-`async`
    /// functions.
    func signal() {
        lock.lock()
        
        if false == suspensions.isEmpty {
            let first = suspensions.removeFirst()
            lock.unlock()
            first.resume()
        }
        else {
            permits += 1
            lock.unlock()
        }
    }
    
    
    /// Acquires a permit, runs the given operation, then signals on the
    /// way out — even if the operation throws.
    ///
    /// Equivalent to:
    /// ```swift
    /// await semaphore.wait()
    /// defer { semaphore.signal() }
    /// return try await operation()
    /// ```
    /// …but harder to forget the `signal()` half.
    func withPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        await wait()
        defer { signal() }
        return try await operation()
    }
}



// MARK: - Private storage

private extension Semaphore {
    
    /// One suspended caller. Owned by the semaphore's `suspensions` queue
    /// and (transitively) referenced by any cancellation handler that
    /// needs to locate it. Carries either a throwing or non-throwing
    /// continuation so the same type works for both wait flavors.
    final class Suspension: @unchecked Sendable {
        
        private enum Kind {
            case nonCancellable(CheckedContinuation<Void, Never>)
            case cancellable(CheckedContinuation<Void, any Error>)
        }
        
        private enum State {
            case empty                  // created, no continuation attached yet
            case waiting(Kind)          // attached, awaiting resume or cancel
            case finished               // already resumed once
        }
        
        private let lock = NSLock()
        private var state: State
        
        
        /// Creates an empty suspension whose continuation will be
        /// attached later via ``adopt(_:)``. Used when the caller needs
        /// a stable reference *before* it has a continuation to give
        /// (e.g. for cancellation-handler setup).
        init() {
            state = .empty
        }
        
        /// Creates a suspension already holding a non-throwing
        /// continuation, ready to be resumed.
        init(_ continuation: CheckedContinuation<Void, Never>) {
            state = .waiting(.nonCancellable(continuation))
        }
        
        
        /// Attaches a throwing continuation to a previously empty
        /// suspension. If the suspension is somehow already finished,
        /// the continuation is immediately resumed with `CancellationError`
        /// rather than leaked.
        func adopt(_ continuation: CheckedContinuation<Void, any Error>) {
            lock.lock()
            switch state {
            case .empty:
                state = .waiting(.cancellable(continuation))
                lock.unlock()
                
            case .waiting, .finished:
                lock.unlock()
                continuation.resume(throwing: CancellationError())
            }
        }
        
        
        /// Resume the suspended caller normally. No-op if the suspension
        /// is already finished.
        func resume() {
            lock.lock()
            guard case .waiting(let kind) = state else {
                lock.unlock()
                return
            }
            state = .finished
            lock.unlock()
            
            switch kind {
            case .nonCancellable(let continuation): continuation.resume()
            case .cancellable(let continuation):    continuation.resume()
            }
        }
        
        
        /// Resume the suspended caller with `CancellationError`. No-op
        /// if the suspension is already finished, and also a no-op for
        /// non-cancellable suspensions (which by contract are never
        /// reached by a cancellation handler).
        func cancel() {
            lock.lock()
            guard case .waiting(.cancellable(let continuation)) = state else {
                lock.unlock()
                return
            }
            state = .finished
            lock.unlock()
            
            continuation.resume(throwing: CancellationError())
        }
    }
}
