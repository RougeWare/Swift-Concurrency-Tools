//
//  TestActor.swift
//  ConcurrencyTools
//
//  Created by Ky on 2023-05-22.
//  Updated for Swift 6 strict concurrency on 2026-05-14.
//

import Foundation



/// A small async fixture used by `desync` and `resync` tests. Each method
/// sleeps for a short interval then returns (or throws to return) a random
/// `Int`, which lets us exercise the bridges between sync and async without
/// pulling in production code.
actor TestActor {
    
    @Sendable
    func int_nothrow() async -> Int {
        await int_nothrow(sleepSeconds: .init(Self.defaultSleepTime))
    }
    
    
    @Sendable
    func int_nothrow(sleepSeconds: UInt8) async -> Int {
        await Task.detached(priority: .low) {
            // If the sleep is cancelled we still want to return *something*,
            // since this variant is the non-throwing one.
            try? await Task.sleep(for: .seconds(Double(sleepSeconds)))
            return Int.random(in: .min ... .max)
        }
        .value
    }
    
    
    @Sendable
    func int() async throws -> Int {
        try await int(sleepSeconds: .init(Self.defaultSleepTime))
    }
    
    
    @Sendable
    func int(sleepSeconds: UInt8) async throws -> Int {
        try await Task.detached(priority: .low) {
            try await Task.sleep(for: .seconds(Double(sleepSeconds)))
            return Int.random(in: .min ... .max)
        }
        .value
    }
}



extension TestActor {
    
    /// Shared instance used by tests. `let` (not `var`) so Swift 6 treats it
    /// as concurrency-safe shared state — the actor's own isolation handles
    /// the rest.
    static let `default` = TestActor()
    
    /// A small random delay so tests don't all sleep for exactly the same
    /// time — useful for surfacing ordering bugs.
    static var defaultSleepTime: TimeInterval { .random(in: 0.5...2) }
}
