//
//  desync.swift
//  Homebrew App Store
//
//  Created by The Northstar✨ System on 2023-03-09.
//

import Foundation



/// Asynchronously runs the given task, then calls `callback` on that thread, and returns the result via the given `callback`. "De-synchronizes" the given async task.
///
/// This returns immediately. Since `callback` is called on an arbitrary thread, you might want to process it on a separate thread using `onMainActor(do:)` or similar
///
/// - Parameters:
///   - task:     The task to run on a separate thread
///   - callback: Passed the return value of `task` after it completes, on the same thread upon which `task` was run
public func desync<Value>(task: @escaping @Sendable () async throws -> Value, callback: @escaping (Result<Value, Error>) -> Void) {
    Task {
        do {
            callback(.success(try await task()))
        }
        catch {
            callback(.failure(error))
        }
    }
}



public extension Task where Failure == any Error {
    /// Asynchronously runs the given task, then calls `callback` on that thread, and returns the result via the given `callback`. "De-synchronizes" the given async task.
    ///
    /// This returns immediately. Since `callback` is called on an arbitrary thread, you might want to process it on a separate thread using `onMainActor(do:)` or similar
    ///
    /// - Parameters:
    ///   - task:     The task to run on a separate thread
    ///   - callback: Passed the return value of `task` after it completes, on the same thread upon which `task` was run
    static func desync(_ task: @escaping @Sendable () async throws -> Success, callback: @escaping (Result<Success, Failure>) -> Void) {
        ConcurrencyTools.desync(task: task, callback: callback)
    }
}
