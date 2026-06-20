//
//  AsyncBinding.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-01-24.
//

import Combine
import FunctionTools



/// A `Lazy` implementation where the value generator acts asynchronously and might throw a failure
public struct ThrowingAsyncLazy<Value, Failure>: Sendable
where Value: Sendable,
      Failure: Error & Sendable
{
    public typealias BindingAnalog = ThrowingAsyncBinding<Value, Failure>
    public typealias Result = BindingAnalog.Result
    public typealias LoadingState = BindingAnalog.LoadingState
    public typealias Get = BindingAnalog.Get
    public typealias Publisher = BindingAnalog.Publisher
    
    
    
    /// The actual way the value is stored/managed
    private var storage: BindingAnalog
    
    
    /// Create a new async binding, whose value will be lazily loaded from `get` the first time it's requested.
    ///
    /// - Parameters:
    ///   - get:         Generates the value that this binds. This is only called when it hasn't been called before.
    ///   - onDidChange: _optional_ - If you prefer to use callbacks instead of publishers to listen for changes, provide one here. Otherwise, subscribe to ``publisher``
    public init(get: @escaping Get) {
        self.storage = .init(get, set: blackhole)
    }
    
    
    /// Create a new async binding set to the given initial value.
    ///
    /// The given value is immediately available for anyone accessing this binding
    ///
    /// - Parameters:
    ///   - initialValue: The initial value to be immediately available of this binding.
    ///   - onDidChange:  _optional_ - If you prefer to use callbacks instead of publishers to listen for changes, provide one here. Otherwise, subscribe to ``publisher``
    public init(_ initialValue: Value) {
        self.storage = .init(initialValue)
    }
}



// MARK: - API - get

public extension ThrowingAsyncLazy {
    
    /// The value that's lazily-loaded.
    ///
    /// This blocks the current context until this lazy value is loaded or if there's an error failing to load. If that value is never loaded and also loading never throws an error, then this blocks indefinitely.
    ///
    /// If a success or failure already exists, then this returns/throws immediately. Otherwise, this pauses until one of those is reached.
    ///
    /// - Returns: The lazy value
    /// - Throws: Any error that occurred trying to load the lazy value
    var wrappedValue: Value {
        get async throws(Failure) {
            try await storage.wrappedValue
        }
    }
    
    
    /// The current state of loading this binding.
    ///
    /// This automatically starts loading if it's not yet started. If you need to peek at the current state without starting to load it, use ``publisher``
    var loadingState: LoadingState {
        return storage.loadingState
    }
}
