//
//  Semaphore.swift
//  ConcurrencyTools
//
//  Created by Ky on 2025-05-08.
//

import Foundation



/// Among other things, this allows you to pause one context to wait until another context says it's ready.
///
/// When you call `wait()` more than once before calling `signal()`, all those `wait()` callsites are paused at the same time. When you call `signal()`, it only resumes the most-recent `wait()` which hasn't yet been `signal()`ed.
///
// /// If you deinitialize an instance of this `Semaphore`, then all the sites which were `wait()`ing immediately resume.
///
///
/// ## Learn about semaphores
/// To learn more about how semaphores work, see:
/// https://en.wikipedia.org/wiki/Semaphore_(programming)
///
///
///
/// ## Technical details
/// A semaphore can control access to a resource across multiple concurrency contexts through use of a traditional counting semaphore and structured concurrency.
///
/// This is an efficient implementation of a traditional counting semaphore. It will only call down to the kernel when the calling context needs to be blocked. If it does not need to block, no kernel call is made.
///
// /// Deinitialization of this type causes `signal()` to be repeated until all `wait()` sites have been signaled.
///
///
// /// - Attention: If instance of this `Semaphore` has only 1 reference, and that reference goes out of scope, or is set to `nil`, or is set to another value, then **all** the sites which were `wait()`ing immediately resume. This is because when the reference count hits `0`, there is no longer any way to manually signal waiting sites, and so a deadlock would occur if this automatic signaling didn't take place.
// FIXME: Each `semaphore.wait()` callsite is a strong reference to that `semaphore`, which causes it to remain allocated and the `deinit` block unreachable if all non-`wait()`ing references to `semaphore` leave scope
public final class Semaphore: Sendable {
    
    /// Drives the actual pausing/resuming
    private let _dispatchSemaphore: DispatchSemaphore
    
    
    /// Creates a new semaphore with the given initial value
    ///
    /// - Parameter value: _optional_ - This technical value controls the initial internal state of the semaphore. If you don't already know about the values of counting semaphores, consult learning resources like [Wikipedia](https://en.wikipedia.org/wiki/Semaphore_(programming)#Semantics_and_implementation)
    public init(_value value: UInt = 0) {
        _dispatchSemaphore = .init(value: .init(value))
    }
    
    
    deinit {
        while signal() {}
    }
}



public extension Semaphore {
    
    /// Causes one `wait()` callsite to resume.
    ///
    /// To signal all `wait()` callsites, deinitialize this `Semaphore` instance
    ///
    /// - Returns: _optional_ - `true` iff a `wait()` call is resumed. `false` if not.
    @discardableResult
    func signal() -> Bool {
        0 != _dispatchSemaphore.signal()
    }
    
    
    /// Pauses execution until the semaphore is signaled again.
    ///
    /// Deinitializing this `Semaphore` will immediately cause this and all of its other `wait()` callsites to stop waiting.
    func wait() async {
        await withCheckedContinuation { [weak _dispatchSemaphore] continuation in
            _dispatchSemaphore?.wait()
            continuation.resume()
        }
    }
    
    
    /// Identical to ``wait()``, but if the given amount of time elapses without signalling this semaphore, this resumes and throws a ``WaitTimedOut`` error.
    ///
    /// Of course, if this semaphore is signaled before the timeout is reached, no error is thrown.
    ///
    /// - Parameter timeout: The amount of time to wait before throwing and resuming. Passing a value less than zero is the same as calling ``wait()``
    func wait(timeout: DispatchTime) async throws(WaitTimedOut) {
        do {
            try await withCheckedThrowingContinuation { [weak _dispatchSemaphore] continuation in
                let result = _dispatchSemaphore?.wait(timeout: timeout)
                
                switch result {
                case .success:         continuation.resume()
                case .none, .timedOut: continuation.resume(throwing: WaitTimedOut())
                }
            }
        }
        catch {
            throw WaitTimedOut()
        }
    }
    
    
    /// Identical to ``wait()``, but if the given amount of time elapses without signalling this semaphore, this resumes and throws a ``WaitTimedOut`` error.
    ///
    /// Of course, if this semaphore is signaled before the timeout is reached, no error is thrown.
    ///
    /// - Parameter timeout: The amount of time to wait before throwing and resuming. Passing a value less than zero is the same as calling ``wait()``
    func wait(timeout: TimeInterval) async throws(WaitTimedOut) {
        try await wait(timeout: DispatchTime.now() + timeout)
    }
    
    
    /// Identical to ``wait()``, but if the given amount of time elapses without signalling this semaphore, this resumes and throws a ``WaitTimedOut`` error.
    ///
    /// Of course, if this semaphore is signaled before the timeout is reached, no error is thrown.
    ///
    /// - Parameter timeout: The amount of time to wait before throwing and resuming. Passing a value less than zero is the same as calling ``wait()``
    @available(macOS 13.0, *)
    func wait(timeout: Duration) async throws(WaitTimedOut) {
        try await wait(timeout: TimeInterval(timeout))
    }
}



public extension Semaphore {
    struct WaitTimedOut: Error {}
}



@available(macOS 13.0, *)
private extension TimeInterval {
    init(_ duration: Duration) {
        let components = duration.components
        self = .init(components.seconds) + (.init(components.attoseconds) / .attosecondsPerSecond)
    }
    
    
    
    private static let attosecondsPerSecond: Self = 1e18
}
