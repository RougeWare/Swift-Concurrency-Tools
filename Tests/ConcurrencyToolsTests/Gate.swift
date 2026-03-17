//
//  Gate.swift
//  ConcurrencyTools
//
//  Created by Ky directing Claude 4.6 Sonnet on 2026-03-06.
//

import Foundation



/// Controls a suspension point in a test, allowing one task to park and another to release it at a precise moment.
///
/// Used to manufacture deterministic interleaving in concurrency tests without relying on sleep-based timing
public actor Gate {
    
    /// Stores the continuation created in ``suspend()``
    private var stored: CheckedContinuation<Void, Never>?
    
    
    public init() {}
}



// MARK: - API

public extension Gate {
    
    /// Suspends the caller here until ``resume()`` is called from elsewhere
    func suspend() async {
        await withCheckedContinuation { stored = $0 }
    }
    
    
    /// Releases whatever task is parked by ``suspend()``
    func resume() {
        stored?.resume()
        stored = nil
    }
}
