//
//  AsyncBinding.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-01-24.
//  Parts of this file were made by Ky directing Claude 4.6 Sonnet.
//

@preconcurrency import Combine

import FunctionTools
@preconcurrency import SafePointer



// This is the "base class". `AsyncBinding`, `ThrowingAsyncLazy`, and `AsyncLazy` are all thin wrappers around `ThrowingAsyncBinding`.

/// A `Binding` implementation where the value getter/setter act asynchronously and might throw a failure.
@available(macOS 12, *)
@available(iOS 15, *)
public struct ThrowingAsyncBinding<Value, Failure>: Sendable
where Value: Sendable,
      Failure: Error,
      Failure: Sendable
{
    public typealias Result = Swift.Result<Value, Failure>
    public typealias LoadingState = ConcurrencyTools.FailableLoadingState<Value, Failure>
    public typealias Get = @Sendable () async throws(Failure) -> Value
    public typealias OnDidChange = @Sendable (LoadingState) async -> Void
    public typealias ThrowingMutateWrappedValue = @Sendable (inout Result) async throws(Failure) -> Void
    public typealias SetWrappedValue = @Sendable (inout Value) async -> Void
    public typealias Publisher = AnyPublisher<LoadingState, Never>
    
    private typealias Subject = CurrentValueSubject<LoadingState, Never>
    
    
    
    /// The actual storage of the value andor its loading state
    private let subject: Subject
    
    /// This holds the mechanism that generates the value, as provided by whoever initialized this struct
    @MutableSafePointer
    private var valueGenerator: ValueGenerator
    
//    /// If the dev wants to listen for changes with a callback, they set this on init
//    private var onDidChange: OnDidChange?
    
    private var onDidChange_shim: Set<AnyCancellable> = []
    
    /// Guarantees exclusive access to getting the value
    private let getterMutex = Mutex()
    
    /// Guarantees exclusive access to setting the value
    private let setterMutex = Mutex()
    
    
    /// **Internal use only.**
    /// 
    /// Create a new async binding, using the given subject to track the loading and value generator to perform the loading (and respond to changes).
    /// 
    /// - Parameters:
    ///   - subject:        Tracks & reports the loading of the bound value
    ///   - valueGenerator: Generates (and responds to changes of) the bound value
    ///   - onDidChange:    _optional_ - If you prefer to use callbacks instead of publishers to listen for changes, provide one here. Otherwise, subscribe to ``publisher``
    private init(subject: Subject, valueGenerator: ValueGenerator, set onDidChange: OnDidChange? = nil) {
        self.subject = subject
        self._valueGenerator = MutableSafePointer(to: valueGenerator)
//        self.onDidChange = onDidChange
        
        subject.sink { newState in
            Task { await onDidChange?(newState) }
        }
        .store(in: &onDidChange_shim)
    }
    
    
    /// Create a new async binding set to the given initial value.
    ///
    /// The given value is immediately available for anyone accessing this binding
    ///
    /// - Parameters:
    ///   - initialValue: The initial value to be immediately available of this binding.
    ///   - onDidChange:  _optional_ - If you prefer to use callbacks instead of publishers to listen for changes, provide one here. Otherwise, subscribe to ``publisher``
    public init(_ initialValue: Value, set onDidChange: OnDidChange? = nil) {
        let initialResult = Result.success(initialValue)
        self.init(subject: Subject(.init(initialResult)),
                  valueGenerator: .init(cache: initialResult, generator: { initialValue }),
                  set: onDidChange)
    }
    
    
    /// Create a new async binding, whose value will be lazily loaded from `get` the first time it's requested.
    ///
    /// - Parameters:
    ///   - get:         Generates the value that this binds. This is only called when it hasn't been called before.
    ///                  If this throws an error, that error is stored and re-thrown every time ``wrappedValue`` is called until/unless a success value is written to this binding using ``mutateWrappedValue(throwingSetter:)``, ``setWrappedValue(_:)``, or by calling ``refresh()`` when this `get` is prepared to return a success value..
    ///   - onDidChange: _optional_ - If you prefer to use callbacks instead of publishers to listen for changes, provide one here. Otherwise, subscribe to ``publisher``
    public init(_ get: @escaping Get, set onDidChange: OnDidChange? = nil) {
        self.init(subject: Subject(.notStarted),
                  valueGenerator: .init(generator: get),
                  set: onDidChange)
    }
}



// MARK: - API - get

@available(macOS 12, *)
@available(iOS 15, *)
public extension ThrowingAsyncBinding {
    
    /// The value inside this binding.
    ///
    /// This blocks the current context until this binding's value is provided or it throws an error failing to load. If that value is never provided or loading never throws an error, then this blocks indefinitely.
    ///
    /// If a success or failure already exists, then this returns/throws immediately. Otherwise, this pauses until one of those is reached.
    ///
    /// - Returns: The bound value
    /// - Throws: Any error that occurred trying to get the bound value
    var wrappedValue: Value {
        get async throws(Failure) {
            switch loadingState {
            // If we already have a terminal state, return it immediately
            case let .success(value):
                return value
            case let .failure(error):
                throw error
                
            // Otherwise, wait for a terminal state
            case .notStarted, .loading:
                for await state in subject.values {
                    switch state {
                    case .notStarted, .loading:
                        // Since the `subject` isn't actually a specific collection, but instead a data stream of this binding's loading state, we "loop" until it's something we can use. Keep in mind the loop pauses automatically when there's no new values, so this isn't a spinlock
                        continue
                        
                    case .success(let value):
                        return value
                        
                    case .failure(let error):
                        throw error
                    }
                }
                
                // `CurrentValueSubject<LoadingState, Never>`'s `.values` sequence can Never terminate.
                // This whole object will be deallocated before that, killing the loop before it gets to this fatal error.
                fatalError("Unexpected terminal state in AsyncBinding.wrappedValue")
            }
        }
    }
    
    
    /// The current state of loading this binding.
    ///
    /// This automatically starts loading if it's not yet started. If you need to peek at the current state without starting to load it, use ``publisher``
    var loadingState: LoadingState {
        startLoading()
        return subject.value
    }
}



// MARK: - API - mutate

@available(macOS 12, *)
@available(iOS 15, *)
public extension ThrowingAsyncBinding {
    
    /// Mutates the currently-held value, andor performs some action if there is no such value but instead a failure.
    ///
    /// - Attention:
    ///   Calling this _never_ changes how the value was initially generated. If ``refresh()`` is called, the original getter is called again, _not_ this.
    ///
    /// - Note:
    ///   The given function will have exclusive access to the value/failure wrapped in this binding, until it exits. That blocks anyone else from setting the value until the given function returns, but anything can still read the previous value until then.
    ///
    ///   Similarly, if something else is currently mutating/setting the value, then this will wait until that's done. If that never ends, this waits forever.
    ///
    /// - Parameters:
    ///   - throwingSetter: This function takes in the current value (or failure) and mutates it to a new value (or failure), which is saved after this `setter` function returns.
    ///                     If this `setter` function throws an error, that error is stored as the new failure in this binding.
    nonmutating func mutateWrappedValue(throwingSetter: ThrowingMutateWrappedValue) async {
        // Phase 1: get current state
        let result = await Result { () async throws(Failure) -> Value in // boilerplate necessary due to https://github.com/swiftlang/swift/issues/87556
            try await self.wrappedValue
        }
        
        // Phase 2: atomic mutation
        await setterMutex.run {
            do {
                var result = result
                try await throwingSetter(&result)
                update(toValue: try result.get())
            }
            catch let error as Failure { // boilerplate necessary due to https://github.com/swiftlang/swift/issues/87556
                update(toFailure: error)
            }
            catch {
                assertionFailure("Unexpected error: \(error)")
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
    nonmutating func setWrappedValue(_ newValue: Value) async {
        await setterMutex.run {
            update(toValue: newValue)
        }
    }
}



// MARK: - API - reset

@available(macOS 12, *)
@available(iOS 15, *)
public extension ThrowingAsyncBinding {
    
    /// Delete the stored value/failure and start loading a new one from the getter supplied when this binding was initialized.
    ///
    /// If this binding was initialized with a single value rather than a getter function, then that value immediately becomes available once again.
    func refresh() {
        valueGenerator.reset()
        initializeInBackground()
    }
}



// MARK: - loading

@available(macOS 12, *)
@available(iOS 15, *)
private extension ThrowingAsyncBinding {
    
    /// Immediately start loading the value inside the binding.
    ///
    /// If the value is already loading, or has already succeeded/failed to load, this does nothing.
    func startLoading() {
        switch subject.value {
        case .loading,
                .success(_),
                .failure(_):
            return
            
        case .notStarted:
            initializeInBackground()
        }
    }
    
    
    /// In a background context, this initializes the wrapped value as described when this binding was initialized
    private func initializeInBackground() {
        subject.send(.loading)
        Task {
            await initialize(lazyValue)
        }
    }
    
    
    /// Immediately initialize the wrapped value to the result of the given function.
    ///
    /// This eventually\* sets the current value regardless of whether one was generated previously.
    ///
    /// \*if `get` never returns, the value is never changed and the state is perpetually `.loading`.
    ///
    /// - Note: Since this acts as a setter, it retains exclusive access to setting the wrapped value. Nothing else can set the wrapped value while this runs, including ``setWrappedValue(_:)``.
    ///
    /// - Parameter get: Generates the value/failure to be stored in this binding
    private func initialize(_ get: @escaping Get) async {
        @Sendable func swift_issue_87556(_ get: @escaping Get) async {
            subject.send(.loading)
            do {
                update(toValue: try await get())
            }
            catch {
                update(toFailure: error)
            }
        }
        
        
        await setterMutex.run {
            await swift_issue_87556(get)
        }
    }
    
    
    /// Immedaitely updates this binding to hold the given value
    private func update(toValue newValue: Value) {
        subject.send(.success(newValue))
    }
    
    
    /// Immedaitely updates this binding to hold the given failure
    private func update(toFailure newFailure: Failure) {
        subject.send(.failure(newFailure))
    }
    
    
    /// The loaded value/failure if it's already been loaded. Otherwise, this loads it and caches the result before returning/throwing.
    @Sendable
    private func lazyValue() async throws(Failure) -> Value {
        try await getterMutex.run { () throws(Failure) -> Value in
            if let cachedValue = try valueGenerator.cache?.get() {
                return cachedValue
            }
            else {
                let value = await Result(catching: valueGenerator.generator)
                valueGenerator.cache = value
                return try value.get()
            }
        }
    }
}



// MARK: Storage

@available(macOS 12, *)
@available(iOS 15, *)
private extension ThrowingAsyncBinding {
    
    /// Describes how the value is generated
    struct ValueGenerator: Sendable {
        
        /// The `value` is static; just read this each time
        var cache: Result?
        
        /// Generates the value. Whether or not the generator succeeds, the resulting value/error is stored forever
        let generator: Get
        
        
        /// Resets this value generator to its initial state
        mutating func reset() {
            cache = nil
        }
    }
}
