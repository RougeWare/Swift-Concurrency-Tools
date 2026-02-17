//
//  resync.swift
//  ConcurrencyTools
//
//  Created by Ky on 2023-01-17.
//

import Foundation

import FunctionTools
import OptionalTools
import SafePointer



/// Converts the given `async` function to a synchronous function.
///
/// This works by executing the given async function in the background, waiting for the result, then returning the result
///
/// - Parameters:
///   - timeout:      _optional_ - How long to wait for the async function to complete before giving up. `nil` signifies to wait forever. Defaults to `nil`
///   - asyncFunction: The function to convert into a synchronous one
public func resync<Value>(timeout: DispatchTime? = nil,
                          _ asyncFunction: @escaping @Sendable () async throws -> Value)
    throws -> Value
    where Value: Sendable
{
    let semaphore = DispatchSemaphore.default
    
    var result: Result<Value, Error>!
    
    Task.detached(priority: .high) {
        defer {
            semaphore.signal()
        }
        
        do {
            result = .success(try await asyncFunction())
        }
        catch {
            result = .failure(error)
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
    
    return try result.unwrappedOrThrow(error: TaskNeverExecutedError()).get()
}


/// Converts the given `async` function to a synchronous function.
///
/// This works by executing the given async function in the background, waiting for the result, then returning the result
///
/// - Parameters:
///   - asyncFunction: The function to convert into a synchronous one
public func resync<Value: Sendable>(_ asyncFunction: @escaping @Sendable () async -> Value) -> Value {
    let semaphore = DispatchSemaphore.default
    
    var result: Value!
    
    Task.detached(priority: .high) {
        defer {
            semaphore.signal()
        }
        
        result = await asyncFunction()
    }
    
    semaphore.wait()
    
    // Okay, so.
    // We generally do not use exclamation points in code. In fact, Our own style guide even says to not use them!
    // https://swift-style-guidelines.bhstudios.org/Cocoa-Xcode-and-Swift-Specific-Features/#do-not-use-exclamation-points
    //
    // However, We're fairly sure that this won't fail to succeed because of the checks above, which have no time limit.
    // If, however, something goes wrong and we get here without a result, it'll crash with a more descriptive error
    // than simple force-unwrapping
    return try! result.unwrappedOrThrow(error: TaskNeverExecutedError())
}


/// Converts the given `async` function to a synchronous function.
///
/// This works by executing the given async function in the background, waiting for it to complete, and then resuming
///
/// - Parameters:
///   - asyncFunction: The function to convert into a synchronous one
public func resync(_ asyncFunction: @escaping @Sendable () async -> Void) {
    let semaphore = DispatchSemaphore.default
    
    Task.detached(priority: .high) {
        defer {
            semaphore.signal()
        }
        
        await asyncFunction()
    }
    
    semaphore.wait()
}



/// This error indicates that a task was started but never finished executing, or didn't finish on-time, or finished without running its closure
struct TaskNeverExecutedError: LocalizedError {
    var errorDescription: String? {
        "Attempted to run a background task, but the task didn't finish as expected"
    }
}


//
//// MARK: - to be transferred somewhere else
//
//
///// A mutable pointer which carries no danger in its use. If there's a crash, it won't be `MutableSafePointer`'s fault!
//private final actor MutableConcurrencySafePointer<Pointee>: Sendable, @preconcurrency MutablePointer
//    where Pointee: Sendable
//{
//    
//    /// Stores the value to be retrieved & mutatd later by `pointer`, including notifying anyone listening.
//    private var _pointee: Pointee
//    
//    /// The function which will be called after `pointee` changes
//    private let onPointeeDidChange: OnPointeeDidChange
//    
//    
//    public init(to pointee: Pointee, onPointeeDidChange: @escaping @Sendable OnPointeeDidChange) {
//        self.onPointeeDidChange = onPointeeDidChange
//        self._pointee = pointee
//    }
//    
//    
//    /// The same as `.init(to:)`
//    ///
//    /// - Parameter wrappedValue: The pointee
//    @inline(__always)
//    public init(wrappedValue: Pointee) {
//        self.init(to: wrappedValue)
//    }
//    
//    
//    public init(to pointee: Pointee) {
//        self.init(to: pointee, onPointeeDidChange: null)
//    }
//    
//    
//    public var pointee: Pointee {
//        get { _pointee }
//        set {
//            let oldValue = _pointee
//            _pointee = newValue
//            onPointeeDidChange(oldValue, newValue)
//        }
//    }
//    
//    
//    nonisolated internal var __UNSAFE_NONISOLATED__pointee: Pointee {
//        get {
//            _pointee
//        }
//    }
//    
//    
//    func setPointee(_ newValue: Pointee) {
//        self.pointee = newValue
//    }
//    
//    
//    public var wrappedValue: Pointee {
//        get { self.pointee }
//        set { self.pointee = newValue }
//    }
//}
//
//
//
//public typealias SafeMutablePointer<Value> = MutableSafePointer<Value>
//
