// Mutex.swift
//
//  Mutex.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-02-24.
//

import Foundation



/// A mutual-exclusivity async lock which maintains strict structural concurrency.
///
/// Only one task at a time can read or change the value. If a second task tries to access it while the first is still working, it waits in line until its turn comes.
///
/// Tasks are served in the order they arrived (first-in, first-out), so no task can be skipped or starved.
///
/// Basic usage:
/// ```
/// let balance = Mutex(100)
///
/// await balance.run { value in
///     value += 50
/// }
/// ```
///
/// You can also use this as an exclusive access queue without a value:
/// ```
/// let mutex = Mutex()
///
/// await mutex.run {
///     loadNextValue()
/// }
/// ```
public actor Mutex<Value: Sendable> {
    
    /// The protected held value
    private var value: Value
    
    /// Tracks whether someone is currently accessing the protected value.
    /// This allows us to only use the queue when there's at least 2 who want access
    private var isSomeoneCurrentlyAccessing = false
    
    /// Tasks that are waiting for their turn
    private var queue: [CheckedContinuation<Void, Never>] = []
    
    
    public init(_ initial: Value) {
        self.value = initial
    }
}



// MARK: - Public API

public extension Mutex {
    
    /// The body of a mutex access run, which takes in the value the mutex holds, possibly mutates it, and possibly returns some value
    typealias InoutBody<Result> = @Sendable (inout Value) throws -> Result
    typealias OutBody<Result> = @Sendable () async throws -> Result
    
    
    
    /// Runs `body` with exclusive access to the protected value, then waits for it to complete, then releases the lock so the next waiting task can proceed. Once this function returns, the body has completed running
    ///
    /// If another task is already inside `run`, this call will pause and wait until it is this task's turn. The wait is automatic and doesn't burn CPU time.
    ///
    /// You can read, modify, or replace the value inside `body`. Whatever state it is in when `body` returns becomes the new protected value.
    ///
    /// If you need to make `async` calls, omit the value parameter of the `body`.
    ///
    /// - Attention: _AVOID_ exfiltrating the protected value by returning it. Doing so is undefined behavior and can easily cause data races. If you need a snapshot of that value at the end of your closure, make a _copy_ of it, and return that _copy_.
    ///
    /// - Parameter body: A closure that receives the value as an `inout` parameter. You may also return something from `body`; it becomes the return value of `run`.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Re-throws any error thrown by `body`. The lock is always released, even when an error occurs.
    @discardableResult
    func run<Result: Sendable>(_ body: InoutBody<Result>) async rethrows -> Result {
        await acquire()          // wait here if others are queued
        defer { release() }      // always release the "lock", even if `body` throws
        return try body(&value)
    }
    
    
    /// Runs `body` exclusively from all other tasks trying to run, then waits for thw body to complete, then releases the lock so the next waiting task can proceed. Once this function returns, the body has completed running
    ///
    /// If another task is already inside `run`, this call will pause and wait until it is this task's turn. The wait is automatic and doesn't burn CPU time.
    ///
    /// This variant of this function ignores the wrapped value. This is useful for many reasons; for instance, this version allows you to `await` within the body, since it doesn't handle any inout values (which have to remain within concurrency barriers).
    ///
    /// If you need access to the value inside `body`, specify it as an inout parameter and eliminate all `await` calls within the body.
    ///
    /// - Parameter body: A closure that runs exclusively from all other tasks run on this mutex. You may also return something from `body`; it becomes the return value of `run`.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Re-throws any error thrown by `body`. The lock is always released, even when an error occurs.
    @discardableResult
    func run<Result: Sendable>(_ body: OutBody<Result>) async rethrows -> Result {
        await acquire()          // wait here if others are queued
        defer { release() }      // always release the "lock", even if `body` throws
        return try await body()
    }
}



public extension Mutex where Value == Void {
    
    /// If you just want to use the Mutex as a general mutual-exclusivity lock without a held value, use this initializer.
    init() {
        self.init(())
    }
}



// MARK: - Private state machine

private extension Mutex {
    
    /// Takes the lock if it's free, or parks this task until it's our turn.
    func acquire() async {
        guard isSomeoneCurrentlyAccessing else {
            // Fast path: lock was free
            isSomeoneCurrentlyAccessing = true
            return
        }
        
        // Slow path: park this task by capturing its continuation.
        // The actor is free to serve earlier callers while this one waits
        await withCheckedContinuation { continuation in
            queue.append(continuation)
        }
        // When we resume here the lock has been handed to us by `release()`.
    }
    
    
    /// Hands the lock to the next task in line, or marks this mutex as free if no one is waiting.
    func release() {
        if let next = queue.first {
            queue.removeFirst()
            
            // The next waiter now owns the lock
            next.resume()
        }
        else {
            // No more in the queue; next lock is free
            isSomeoneCurrentlyAccessing = false
        }
    }
}
