//
//  resync.swift
//  Plural Diagramming
//
//  Created by The Northstar✨ System on 2023-01-17.
//

import Foundation

import OptionalTools
import SafePointer
import SimpleLogging



/// Converts the given `async` function to a synchronous function.
///
/// This works by executing the given async function in the background, waiting for the result, then returning the result
///
/// - Parameters:
///   - timeout:      _optional_ - How long to wait for the async function to complete before giving up. `nil` signifies to wait forever. Defaults to `nil`
///   - asyncFunction: The function to convert into a synchronous one
public func resync<Value>(timeout: DispatchTime? = nil,
                          _ asyncFunction: @escaping () async throws -> Value)
throws -> Value {
    let semaphore = DispatchSemaphore.default
    
    let result = MutableSafePointer<Optional<Result<Value, Error>>>(to: .none)
    
    log(verbose: "\(counter)t • 1: Creating task")
    Task.detached(priority: .high) {
        log(verbose: "\(counter)t • 3: Running task")
        
        do {
            log(verbose: "\(counter)t • 4: Calculating...")
            result.pointee = .some(.success(try await asyncFunction()))
            log(verbose: "\(counter)t • 5: Calculated!")
        }
        catch {
            log(warning: "\(counter)t • 5: Calculation threw an error")
            result.pointee = .failure(error)
        }
        
        log(verbose: "\(counter)t • 6: Signaling...")
        let signal = semaphore.signal()
        log(verbose: "\(counter)t • 7: Signaled \(signal)")
    }
    
    log(verbose: "\(counter)t • 2: Waiting...")
    if let timeout {
        let timeoutResult = semaphore.wait(timeout: timeout)
        
        switch timeoutResult {
        case .success:
            log(verbose: "\(counter)t • 8: Done waiting")
            
        case .timedOut:
            log(error: "\(counter)t • 8: Waited too long")
            throw TaskNeverExecutedError()
        }
    }
    else {
        semaphore.wait()
        log(verbose: "\(counter)t • 8: Done waiting")
    }
    
    return try result.pointee.unwrappedOrThrow(error: TaskNeverExecutedError()).get()
}


private var counter = Int()

/// Converts the given `async` function to a synchronous function.
///
/// This works by executing the given async function in the background, waiting for the result, then returning the result
///
/// - Parameters:
///   - asyncFunction: The function to convert into a synchronous one
public func resync<Value>(_ asyncFunction: @escaping () async -> Value) -> Value {
    let semaphore = DispatchSemaphore.default
    
    let result = MutableSafePointer<Optional<Value>>(to: .none)
    
    counter += 1
    
    log(verbose: "\(counter) • 1: Creating task")
    Task.detached(priority: .high) {
        log(verbose: "\(counter) • 3: Running task")
        
        log(verbose: "\(counter) • 4: Calculating...")
        result.pointee = .some(await asyncFunction())
        log(verbose: "\(counter) • 5: Calculated!")
        
        log(verbose: "\(counter) • 6: Signaling...")
        let signal = semaphore.signal()
        log(verbose: "\(counter) • 7: Signaled \(signal)")
    }
    
    log(verbose: "\(counter) • 2: Waiting...")
    semaphore.wait()
    log(verbose: "\(counter) • 8: Done waiting")
    
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
}
