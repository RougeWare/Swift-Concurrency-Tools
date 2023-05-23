//
//  Task + sugar.swift
//  
//
//  Created by Northstar✨System on 2023-05-22.
//

import Foundation



public extension Task where Success == Never, Failure == Never {
    
    /// Suspends the current task for at least the given duration in seconds.
    ///
    /// If the task is canceled before the time ends, this function throws `CancellationError`.
    ///
    /// This function doesn't block the underlying thread.
    static func sleep(seconds: TimeInterval) async throws {
        try await sleep(nanoseconds: .init(seconds) * 1_000_000_000)
    }
}
