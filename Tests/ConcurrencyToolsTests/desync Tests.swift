//
//  desync Tests.swift
//  ConcurrencyTools
//
//  Created by Northstar✨System on 2023-05-22.
//  Migrated to Swift Testing on 2026-05-14.
//

import Testing
import Foundation
import ConcurrencyTools



@Suite("desync")
struct DesyncTests {
    
    /// Verifies that `desync` invokes its callback exactly once with the eventual result.
    ///
    /// The original test used a `DispatchSemaphore` plus a captured `Bool` flag to
    /// confirm the callback fired. Under Swift 6, mutating that flag inside a
    /// `@Sendable` callback is a data race. Bridging through a `CheckedContinuation`
    /// removes both the flag and the semaphore — if the continuation never resumes,
    /// the test's `.timeLimit` fails it for us.
    @Test("Invokes its callback with the result of the wrapped async task",
          .timeLimit(.minutes(1)))
    func invokesCallback() async {
        let result: Result<Int, Error> = await withCheckedContinuation { continuation in
            ConcurrencyTools.desync(task: TestActor.default.int) { result in
                continuation.resume(returning: result)
            }
        }
        
        // The test cares that the callback fired — either outcome is acceptable
        // for proving `desync`'s plumbing works. We surface the value so a future
        // test reader can see what came back if they're debugging.
        switch result {
        case .success(let int):
            print("desync delivered success: \(int)")
        case .failure(let error):
            // TestActor.int can throw on cancellation; that still proves the bridge fired.
            print("desync delivered failure: \(error)")
        }
    }
}
