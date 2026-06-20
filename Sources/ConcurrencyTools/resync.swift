//
//  resync.swift
//  Plural Diagramming
//
//  Created by Ky on 2023-01-17.
//

import Foundation

import OptionalTools
@preconcurrency import SafePointer



/// Converts the given `async` function to a synchronous function.
///
/// This works by executing the given async function in the background, waiting for the result, then returning the result
///
/// - Parameters:
///   - timeout:      _optional_ - How long to wait for the async function to complete before giving up. `nil` signifies to wait forever. Defaults to `nil`
///   - asyncFunction: The function to convert into a synchronous one
@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, macCatalyst 26, *)
public func resync<Value>(timeout: DispatchTime? = nil,
                          _ asyncFunction: @escaping @Sendable () async throws -> Value)
throws -> Value {
    let semaphore = DispatchSemaphore.default
    
    let result = MutableSafePointer<Optional<Result<Value, Error>>>(to: .none)
    
    Task.immediateDetached(priority: .high) {
        defer {
            semaphore.signal()
        }
        
        do {
            result.pointee = .some(.success(try await asyncFunction()))
        }
        catch {
            result.pointee = .failure(error)
        }
    }
    
    if let timeout {
        let timeoutResult = semaphore.wait(timeout: timeout)
        
        switch timeoutResult {
        case .success:
            break
            
        case .timedOut:
            throw TaskNeverExecutedError()
        }
    }
    else {
        semaphore.wait()
    }
    
    return try result.pointee.unwrappedOrThrow(error: TaskNeverExecutedError()).get()
}


/// Converts the given `async` function to a synchronous function.
///
/// This works by executing the given async function in the background, waiting for the result, then returning the result
///
/// - Parameters:
///   - asyncFunction: The function to convert into a synchronous one
@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, macCatalyst 26, *)
public func resync<Value>(_ asyncFunction: @escaping @Sendable () async -> Value) -> Value {
    let semaphore = DispatchSemaphore.default
    
    let result = MutableSafePointer<Optional<Value>>(to: .none)
    
    Task.immediateDetached(priority: .userInitiated) {
        defer {
            semaphore.signal()
        }
        
        result.pointee = .some(await asyncFunction())
    }
    
    semaphore.wait()
    
    // Okay, so.
    // We generally do not use exclamation points in code. In fact, Our own style guide even says to not use them!
    // https://swift-style-guidelines.bhstudios.org/Cocoa-Xcode-and-Swift-Specific-Features/#do-not-use-exclamation-points
    //
    // However, We're fairly sure that this won't fail to succeed because of the checks above, which have no time limit.
    // If, however, something goes wrong and we get here without a result, it'll crash with a more descriptive error
    // than simple force-unwrapping
    return try! result.pointee.unwrappedOrThrow(error: TaskNeverExecutedError())
}



/// This error indicates that a task was started but never finished executing, or didn't finish on-time, or finished without running its closure
struct TaskNeverExecutedError: LocalizedError {
    var errorDescription: String? {
        "Attempted to run a background task, but the task didn't finish as expected"
    }
    
    
    var recoverySuggestion: String? {
        "File a bug report and be sure to include whatever makes your setup different from the unit tests in this package."
    }
    
    
    var helpAnchor: String? {
        "https://github.com/RougeWare/Swift-Concurrency-Tools/issues/new/choose"
    }
}
