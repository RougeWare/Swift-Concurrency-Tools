//
//  Gate.swift
//  ConcurrencyTools
//
//  Created by Ky directing Claude 4.6 Sonnet on 2026-03-06.
//

import Foundation



/// Controls a suspension point in a test, allowing one task to park and another to release it at a precise moment.
///
/// Use this to manufacture deterministic interleaving in concurrency tests without relying on sleep-based timing.
///
/// ```swift
/// let gate = Gate()
///
/// Task {
///     await doWork()
///     gate.resume()
/// }
///
/// await gate.suspend()
/// ```
public actor Gate {
    
    /// ``resume()`` calls that arrived before a matching ``suspend()``,
    /// banked so the next suspend returns immediately rather than parking.
    private var credits = 0
    
    /// Tasks parked by ``suspend()``, in arrival order.
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    
    /// Prepare a new gate.
    ///
    /// Creation alone doesn't do anything; tou have to use the other methods to operate a gate.
    public init() {}
    
    
    isolated deinit {
        while resume() {}
    }
}



// MARK: - API

public extension Gate {
    
    /// Suspends the caller here until ``resume()`` is called from elsewhere
    func suspend() async {
        if 0 < credits {
            credits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
    
    
    /// Releases whatever task is parked by ``suspend()``
    ///
    /// - Returns: _optional_ - `true` iff all `wait()` calls are resumed when this returns. `false` otherwise.
    @discardableResult
    func resume() -> Bool {
        if let first = waiters.popFirst() {
            first.resume()
            return false
        }
        else {
            credits += 1
            return true
        }
    }
}
