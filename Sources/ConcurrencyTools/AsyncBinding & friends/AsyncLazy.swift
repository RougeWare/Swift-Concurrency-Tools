//
//  AsyncBinding.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-01-24.
//

import FunctionTools



/// A `Lazy` implementation where the value generator acts asynchronously
@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, macCatalyst 26, *)
public struct AsyncLazy<Value>: Sendable
where Value: Sendable
{
    public typealias BindingAnalog = AsyncBinding<Value>
    public typealias LoadingState = BindingAnalog.LoadingState
    public typealias Get = BindingAnalog.Get
    public typealias Publisher = BindingAnalog.Publisher

    
    
    /// The actual way the value is stored/managed
    private var storage: BindingAnalog
    
    
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
    
    
    /// Create a new async binding, whose value will be lazily loaded from `get` the first time it's requested.
    ///
    /// - Parameters:
    ///   - get:         Generates the value that this binds. This is only called when it hasn't been called before.
    ///   - onDidChange: _optional_ - If you prefer to use callbacks instead of publishers to listen for changes, provide one here. Otherwise, subscribe to ``publisher``
    public init(_ initialValue: @escaping Get) {
        self.storage = .init(initialValue)
    }
}



// MARK: - API - get

@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, macCatalyst 26, *)
public extension AsyncLazy {
    
    /// The value that's lazily-loaded.
    ///
    /// This blocks the current context until this lazy value is loaded or if there's an error failing to load. If that value is never loaded and also loading never throws an error, then this blocks indefinitely.
    ///
    /// If a value already exists, then this returns immediately. Otherwise, this pauses until that is reached.
    var wrappedValue: Value {
        get async {
            await storage.wrappedValue
        }
    }
    
    
    /// The current state of loading this binding.
    ///
    /// This automatically starts loading if it's not yet started. If you need to peek at the current state without starting to load it, use ``publisher``
    var loadingState: LoadingState {
        return storage.loadingState
    }
}
