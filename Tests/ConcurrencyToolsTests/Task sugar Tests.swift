//
//  Task sugar Tests.swift
//  ConcurrencyTools
//
//  Created by Ky on 2023-05-22.
//  Migrated to Swift Testing on 2026-05-14.
//

import Testing
import Foundation
import ConcurrencyTools



@Suite("Task sugar")
struct TaskSugarTests {
    
    /// Verifies that `Task.sleep(seconds:)` actually pauses for roughly the requested duration.
    ///
    /// The original test captured two `var` timestamps and mutated them inside an
    /// `@Sendable` async closure — which Swift 6 strict concurrency rightly rejects
    /// as a data race. Returning the timestamps from `resync` keeps the closure free
    /// of captured mutable state.
//    @available(macOS, deprecated: 13, obsoleted: 28)
//    @available(iOS, deprecated: 16, obsoleted: 28)
    @Test("Task.sleep(seconds:) pauses for approximately the requested duration")
    func sleepSeconds() throws {
        guard #unavailable(macOS 28, iOS 28) else { return }
        let sleepSeconds = TimeInterval.random(in: 2 ..< 4)
        
        let (before, after) = try resync { () -> (Date, Date) in
            let before = Date()
            try await Task.sleep(seconds: sleepSeconds)
            let after = Date()
            return (before, after)
        }
        
        let elapsed = after.timeIntervalSince(before)
        let drift = abs(elapsed - sleepSeconds)
        #expect(drift < 1.0, "Expected ~\(sleepSeconds)s, observed \(elapsed)s (drift \(drift)s)")
    }
}
