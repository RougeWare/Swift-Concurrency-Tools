//
//  Task + sugar.swift
//  
//
//  Created by Ky on 2023-05-22.
//

import Foundation



public extension Task where Success == Never, Failure == Never {
    
    /// Suspends the current task for at least the given duration in seconds.
    ///
    /// If the task is canceled before the time ends, this function throws `CancellationError`.
    ///
    /// This function doesn't block the underlying thread.
    @available(macOS, introduced: 10.15, deprecated: 13, obsoleted: 28, renamed: "sleep(for:)", message: "Swift now has a built-in approach to this. Instead, use `sleep(for: .seconds(seconds))`.")
    @available(iOS, introduced: 13, deprecated: 16, obsoleted: 28, renamed: "sleep(for:)", message: "Swift now has a built-in approach to this. Instead, use `sleep(for: .seconds(seconds))`.")
    @available(watchOS, introduced: 6, deprecated: 9, obsoleted: 26, renamed: "sleep(for:)", message: "Swift now has a built-in approach to this. Instead, use `sleep(for: .seconds(seconds))`.")
    @available(tvOS, introduced: 13, deprecated: 16, obsoleted: 26, renamed: "sleep(for:)", message: "Swift now has a built-in approach to this. Instead, use `sleep(for: .seconds(seconds))`.")
    @available(visionOS, deprecated: 1, obsoleted: 26, renamed: "sleep(for:)", message: "Swift now has a built-in approach to this. Instead, use `sleep(for: .seconds(seconds))`.")
    @available(macCatalyst, introduced: 13, deprecated: 16, obsoleted: 26, renamed: "sleep(for:)", message: "Swift now has a built-in approach to this. Instead, use `sleep(for: .seconds(seconds))`.")
    static func sleep(seconds: TimeInterval) async throws {
        try await sleep(nanoseconds: .init(seconds) * 1_000_000_000)
    }
}
