//
//  AsyncBinding.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-01-24.
//

@preconcurrency import Combine



/// A `Binding` implementation where the value getter/setter act asynchronously.
@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, macCatalyst 26, *)
public struct AsyncBinding<Value>: Sendable
where Value: Sendable
{
    public typealias ThrowingAnalog = ThrowingAsyncBinding<Value, Never>
    public typealias LoadingState = ConcurrencyTools.LoadingState<Value>
    public typealias Get = ThrowingAnalog.Get
    public typealias OnDidChange = ThrowingAnalog.OnDidChange
    public typealias MutateWrappedValue = @Sendable (inout Value) async -> Void
    public typealias Publisher = AnyPublisher<LoadingState, Never>

    
    
    /// The actual way the value is stored/managed
    private var storage: ThrowingAnalog
    
    
    /// Create a new async binding set to the given initial value.
    ///
    /// The given value is immediately available for anyone accessing this binding
    ///
    /// - Parameters:
    ///   - initialValue: The initial value to be immediately available of this binding.
    ///   - onDidChange:  _optional_ - If you prefer to use callbacks instead of publishers to listen for changes, provide one here. Otherwise, subscribe to ``publisher``
    public init(_ initialValue: Value, set onDidChange: OnDidChange? = nil) {
        self.storage = .init(initialValue, set: onDidChange)
    }
    
    
    /// Create a new async binding which asks the given getter for the initial value as soon as someone asks for this binding's wrapped value
    ///
    /// - Parameters:
    ///   - get:         Generates the value that this binds. This is only called when it hasn't been called before.
    ///   - onDidChange: _optional_ - If you prefer to use callbacks instead of publishers to listen for changes, provide one here. Otherwise, subscribe to ``publisher``
    public init(_ get: @escaping Get, set onDidChange: OnDidChange? = nil) {
        self.storage = .init(get, set: onDidChange)
    }
}



// MARK: - API - get

@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, macCatalyst 26, *)
public extension AsyncBinding {
    
    /// The value inside this binding.
    ///
    /// This blocks the current context until this binding's value is provided or it throws an error failing to load. If that value is never provided or loading never throws an error, then this blocks indefinitely.
    ///
    /// If a success or failure already exists, then this returns/throws immediately. Otherwise, this pauses until one of those is reached.
    var wrappedValue: Value {
        get async {
            try! await storage.wrappedValue //try!: https://github.com/swiftlang/swift/issues/87036
        }
    }
    
    
    /// The current state of loading this binding.
    ///
    /// This automatically starts loading if it's not yet started. If you need to peek at the current state without starting to load it, use ``publisher``
    var loadingState: LoadingState {
        LoadingState(storage.loadingState)
    }
}



// MARK: - API - mutate

@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, macCatalyst 26, *)
public extension AsyncBinding {
    
    /// Mutates the currently-held value.
    ///
    /// - Attention:
    ///   Calling this _never_ changes how the value was initially generated. If ``refresh()`` is called, the original getter is called again, _not_ this.
    ///
    /// - Note:
    ///   The given function will have exclusive access to the value wrapped in this binding, until it exits. That blocks anyone else from setting the value until the given function returns, but anything can still read the previous value until then.
    ///
    ///   Similarly, if something else is currently mutating/setting the value, then this will wait until that's done. If that never ends, this waits forever.
    ///
    /// - Parameters:
    ///   - setter: This function takes in the current value and mutates it to a new value, which is saved after this `setter` function returns.
    nonmutating func mutateWrappedValue(setter: MutateWrappedValue) async {
        await storage.mutateWrappedValue { result in
            switch result {
            case .success(var value):
                await setter(&value)
                result = .success(value)
                
            case .failure(let error):
                preconditionFailure("Impossible error thrown: \(error)")
            }
        }
    }
    
    
    /// Immediately changes the currently-held value/failure/progress to the given success value.
    ///
    /// If you want to interactively mutate the value in this binding or respond to a current failure state, use ``setWrappedValue(setter:onFailure:)`` or ``setWrappedValue(throwing:throwingSetter:onFailure:)``
    ///
    /// - Note:
    ///   While the given value is being set to be the new value, this function guarantees exclusive access to the value/failure wrapped in this binding, until it exits. This blocks anyone else from setting the value until this function returns, but anything can still read the previous value until then.
    ///
    ///   Similarly, if something else is currently mutating/setting the value, then this will wait until that's done. If that never ends, this waits forever.
    ///
    /// - Parameter newValue: The new value to hold within this binding
    func setWrappedValue(_ value: Value) async {
        try! await storage.setWrappedValue(value) //try!: https://github.com/swiftlang/swift/issues/87036
    }
}



// MARK: - API - reset

@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, macCatalyst 26, *)
public extension AsyncBinding {
    
    /// Delete the stored value and start loading a new one from the getter supplied when this binding was initialized.
    ///
    /// If this binding was initialized with a single value rather than a getter function, then that value immediately becomes available once again.
    func refresh() {
        storage.refresh()
    }
}
