//
//  AsyncBinding.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-01-24.
//  Parts of this file were made by Ky directing Claude 4.6 Sonnet.
//

@preconcurrency import Combine
import SwiftUI

import FunctionTools
@preconcurrency import SafePointer



// MARK: - ThrowingAsyncBinding

// This is the "base class". `AsyncBinding`, `ThrowingAsyncLazy`, and `AsyncLazy` are all thin wrappers around `ThrowingAsyncBinding`.

/// A `Binding` implementation where the value getter/setter act asynchronously and might throw a failure
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
    public typealias Set = @Sendable (Value) async throws(Failure) -> Void
    public typealias ThrowingSetWrappedValue<Thrown: Error> = @Sendable (inout Value) async throws(UpdateSetterError<Thrown>) -> Void
    public typealias SetWrappedValue = @Sendable (inout Value) async -> Void
    public typealias Subject = CurrentValueSubject<LoadingState, Never>
    
    
    
    private let subject: Subject
    
    @MutableSafePointer
    private var valueGenerator: ValueGenerator
    
    private let mutex = Mutex()
    
    
    private init(subject: Subject, valueGenerator: ValueGenerator) {
        self.subject = subject
        self._valueGenerator = MutableSafePointer(to: valueGenerator)
    }
    
    
    public init(initialState: LoadingState = .notStarted,
                get: @escaping Get,
                set: @escaping Set)
    {
        self.init(subject: Subject(initialState),
                  valueGenerator: .dynamic(getter: get, setter: set))
    }
    
    
    public init(_ initialValue: Value) {
        let initialValue = Result.success(initialValue)
        self.init(subject: Subject(.init(initialValue)),
                  valueGenerator: .static(value: initialValue))
    }
    
    
    public init(_ initialValue: @escaping Get) {
        self.init(subject: Subject(.notStarted),
                  valueGenerator: ._generateThenStore(generator: initialValue))
    }
}



// MARK: API - get

@available(macOS 12, *)
@available(iOS 15, *)
public extension ThrowingAsyncBinding {
    
    /// Suspends until the value is successfully loaded or an error occurs.
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
                
            // Otherwise wait for a terminal state
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
    /// This automatically starts loading if it's not yet started. If you need to peek at the current state without starting to load it, call ``peekLoadingState``
    var loadingState: LoadingState {
        startLoading()
        return peekLoadingState
    }
    
    
    /// The current state of loading this binding.
    ///
    /// This just exposes the current state, without changing anything. While useful, ``ThrowingAsyncBinding`` prefers to semantically appear as if it contains the bound value as-needed, so ``loadingState`` is preferred. Only use this when your internal implementation details require that you don't modify whatever state this instance contains
    var peekLoadingState: LoadingState {
        return subject.value
    }
}



// MARK: API - set

@available(macOS 12, *)
@available(iOS 15, *)
public extension ThrowingAsyncBinding {
    
    /// Mutates the currently-held value, or performs some action if there is no such value but instead a failure.
    ///
    /// - Parameters:
    ///   - setter:    This function takes in the current value and mutates it to a new value, which is saved after this `setter` function returns.
    ///                If this `setter` function throws an error, that error is re-thrown from this `setWrappedValue` function and the wrapped value is unaffected.
    ///   - onFailure: _optional_ - Called if a previous attempt to initialize/set the wrapped value failed, meaning there's no value to send to the setter to be mutated.
    ///                If you already have a value and you want to just set the current wrapped value to that, simply pass that value to ``setWrappedValue(_:)``.
    ///                Defaults to a no-op.
    nonmutating func setWrappedValue<Thrown: Error>(
        throwing _: Thrown.Type = Thrown.self,
        throwingSetter: ThrowingSetWrappedValue<Thrown>,
        onFailure: (Failure) -> Void)
    async throws(Thrown) {
        // Phase 1: wait for a terminal state outside the mutex.
        // Holding the mutex here would deadlock against initialize_().
        do { _ = try await self.wrappedValue }
        catch { return onFailure(error) }
        
        
        @Sendable
        func generateOutcome() async -> Swift.Result<Void, Thrown> {
            guard case .success(var current) = peekLoadingState else {
                // A concurrent setter or failure landed between phases. Respect it.
                return .success(())
            }
            do {
                try await throwingSetter(&current)
                update(toValue: current)
                return .success(())
            }
            catch {
                switch error {
                case .setBinding(let failure):
                    update(toFailure: failure)
                    return .success(()) // handled internally, don't propagate
                case .propagate(let thrown):
                    return .failure(thrown)
                }
            }
        }
        
        
        // Phase 2: atomic read-modify-write inside the mutex.
        // .propagate errors are smuggled out via Result rather than thrown
        // directly, since we can't use typed-throws inside the mutex body.
        let outcome = await mutex.run {
            await generateOutcome()
        }
        
        _ = try outcome.get()
    }
    
    
    /// Mutates the currently-held value, or performs some action if there is no such value but instead a failure.
    ///
    /// - Parameters:
    ///   - setter:    This function takes in the current value and mutates it to a new value, which is saved after this `setter` function returns.
    ///                If this `setter` function throws an error, that error is re-thrown from this `setWrappedValue` function and the wrapped value is unaffected.
    ///   - onFailure: _optional_ - Called if a previous attempt to initialize/set the wrapped value failed, meaning there's no value to send to the setter to be mutated.
    ///                If you already have a value and you want to just set the current wrapped value to that, simply pass that value to ``setWrappedValue(_:)``.
    ///                Defaults to a no-op.
    nonmutating func setWrappedValue<Thrown: Error>(
        throwing _: Thrown.Type = Thrown.self,
        throwingSetter: ThrowingSetWrappedValue<Thrown>)
    async throws(Thrown) {
        try await setWrappedValue(
            throwing: Thrown.self,
            throwingSetter: throwingSetter,
            onFailure: update(toFailure:))
    }
    
    
    /// Mutates the currently-held value, or performs some action if there is no such value but instead a failure.
    ///
    /// - Parameters:
    ///   - setter:    This function takes in the current value and mutates it to a new value, which is saved after this `setter` function returns
    ///   - onFailure: _optional_ - Called if a previous attempt to initialize/set the wrapped value failed, meaning there's no value to send to the setter to be mutated.
    ///                If you already have a value and you want to just set the current wrapped value to that, simply pass that value to ``setWrappedValue(_:)``.
    ///                Defaults to a no-op.
    nonmutating func setWrappedValue(setter: SetWrappedValue, onFailure: (Failure) -> Void)  async {
        // Phase 1 — wait for a terminal state, outside the mutex.
        //
        // We must not hold the mutex here: if the binding hasn't loaded yet,
        // `initialize(_:)` needs the mutex to complete, and holding it while
        // waiting for that completion would deadlock.
        //
        // We don't use the value from this call directly, because a concurrent
        // setter may change it before we enter the critical section below.
        do { _ = try await self.wrappedValue }
        catch { return onFailure(error) }

        // Phase 2 — atomic read-modify-write, inside the mutex.
        //
        // Re-reading `subject.value` here (rather than using the snapshot from
        // phase 1) ensures we operate on the most current value, regardless of
        // what concurrent setters did while we were waiting. No call to
        // `wrappedValue` here — that would risk re-entering the mutex or
        // triggering a load.
        await mutex.run {
            switch peekLoadingState {
            case .success(var current):
                await setter(&current)
                update(toValue: current)
            
            case .notStarted, .loading, .failure(_):
                return
            }
        }
    }
    
    
    /// Mutates the currently-held value, or performs some action if there is no such value but instead a failure.
    ///
    /// - Parameters:
    ///   - setter:    This function takes in the current value and mutates it to a new value, which is saved after this `setter` function returns
    ///   - onFailure: _optional_ - Called if a previous attempt to initialize/set the wrapped value failed, meaning there's no value to send to the setter to be mutated.
    ///                If you already have a value and you want to just set the current wrapped value to that, simply pass that value to ``ThrowingAsyncBinding/setWrappedValue(_:)``.
    ///                Defaults to a no-op.
    nonmutating func setWrappedValue(setter: SetWrappedValue) async {
        await setWrappedValue(setter: setter, onFailure: null)
    }
    
    
    /// Immediately changes the currently-held value/failure/progress to the given success value.
    ///
    /// If you want to interactively mutate the value in this binding or respond to a current failure state, use ``setWrappedValue(setter:onFailure:)`` or ``setWrappedValue(throwing:throwingSetter:onFailure:)``
    ///
    /// - Parameter newValue: The new value to immediately update this binding to hold
    nonmutating func setWrappedValue(_ newValue: Value) async {
        await mutex.run {
            update(toValue: newValue)
        }
    }
    
    
    
    typealias UpdateSetterError<ThrownError: Error & Sendable> = ConcurrencyTools.UpdateSetterError<Failure, ThrownError>
}



/// What to do when an error occurs within the update setter block
public enum UpdateSetterError<BindingError: Error, ThrownError: Error & Sendable>: Error {
    case setBinding(BindingError)
    case propagate(ThrownError)
}



// MARK: loading

@available(macOS 12, *)
@available(iOS 15, *)
private extension ThrowingAsyncBinding {
    
    func startLoading() {
        switch subject.value {
        case .loading,
                .success(_),
                .failure(_):
            return
            
        case .notStarted:
            subject.send(.loading)
            Task {
                await initialize_(generateValue)
            }
        }
    }
    
    
    private func initialize_(_ block: @escaping Get) async {
        @Sendable func _initialize(_ block: @escaping Get) async {
            // If a concurrent update already resolved us while we were queued,
            // there's nothing left to do. This makes startLoading() safe to
            // call from multiple concurrent contexts.
            switch subject.value {
            case .success, .failure:
                return
            case .notStarted, .loading:
                break
            }
            
            subject.send(.loading)
            do {
                update(toValue: try await block())
            } catch {
                update(toFailure: error)
            }
        }
        
        
        await mutex.run {
            await _initialize(block)
        }
    }
    
    
    private func update(toValue newValue: Value) {
        subject.send(.success(newValue))
    }
    
    
    private func update(toFailure newFailure: Failure) {
        subject.send(.failure(newFailure))
    }
    
    
    @Sendable
    private func generateValue() async throws(Failure) -> Value {
        switch valueGenerator {
        case .dynamic(getter: let getter, setter: _):
            return try await getter()
            
        case .static(let value):
            return try value.get()
            
        case ._generateThenStore(generator: let generator):
            let value = await Result(catching: generator)
            valueGenerator = .static(value: value)
            return try value.get()
        }
    }
}



// MARK: Storage

@available(macOS 12, *)
@available(iOS 15, *)
private extension ThrowingAsyncBinding {
    /// Describes how the value is generated
    enum ValueGenerator: Sendable {
        /// The `value` is static; just read this each time
        case `static`(value: Result)
        
        /// The value should be generated exactly once by calling the given `generator`. Whether or not the generator succeeds, the resulting value/error is stored forever
        case _generateThenStore(generator: Get)
        
        /// The value is dynamically fetched & written using the given `getter` and `setter` functions
        case dynamic(getter: Get, setter: Set)
    }
}



// MARK: - ThrowingAsyncLazy

/// A `Lazy` implementation where the value generator acts asynchronously and might throw a failure
@available(macOS 12, *)
@available(iOS 15, *)
public struct ThrowingAsyncLazy<Value, Failure>: Sendable
where Value: Sendable,
      Failure: Error & Sendable
{
    public typealias Result = ThrowingAsyncBinding<Value, Failure>.Result
    public typealias LoadingState = ThrowingAsyncBinding<Value, Failure>.LoadingState
    public typealias Get = ThrowingAsyncBinding<Value, Failure>.Get
    
    
    
    private var storage: ThrowingAsyncBinding<Value, Failure>
    
    
    public init(initialState: LoadingState = .notStarted,
                get: @escaping Get) {
        self.storage = .init(initialState: initialState, get: get, set: null)
    }
    
    
    
    public init(_ initialValue: Value) {
        self.storage = .init(initialValue)
    }
    
    
    
    public var wrappedValue: Value {
        get async throws(Failure) {
            try await storage.wrappedValue
        }
    }
}



// MARK: - AsyncBinding

/// A `Binding` implementation where the value getter/setter act asynchronously
@available(macOS 12, *)
@available(iOS 15, *)
public struct AsyncBinding<Value>: Sendable
where Value: Sendable
{
    public typealias ThrowingAnalog = ThrowingAsyncBinding<Value, Never>
    public typealias LoadingState = ThrowingAnalog.LoadingState
    public typealias Get = ThrowingAnalog.Get
    public typealias Set = ThrowingAnalog.Set
    
    
    
    private var storage: ThrowingAnalog
    
    
    public init(initialState: LoadingState = .notStarted,
                get: @escaping Get,
                set: @escaping Set)
    {
        self.storage = .init(initialState: initialState, get: get, set: null)
    }
    
    
    
    public init(_ initialValue: Value) {
        self.storage = .init(initialValue)
    }
    
    
    public init(_ initialValue: @escaping Get) {
        self.storage = .init(initialValue)
    }
}



@available(macOS 12, *)
@available(iOS 15, *)
public extension AsyncBinding {
    var wrappedValue: Value {
        get async {
            try! await storage.wrappedValue
        }
    }
    
    
    func setWrappedValue(_ value: Value) async {
        try! await storage.setWrappedValue(value)
    }
    
    
    var loadingState: LoadingState {
        return storage.loadingState
    }
}



// MARK: - AsyncLazy

/// A `Lazy` implementation where the value generator acts asynchronously
@available(macOS 12, *)
@available(iOS 15, *)
public struct AsyncLazy<Value>: Sendable
where Value: Sendable
{
    public typealias BindingAnalog = AsyncBinding<Value>
    public typealias LoadingState = BindingAnalog.LoadingState
    public typealias Get = BindingAnalog.Get
    
    
    
    private var storage: BindingAnalog
    
    
    public init(initialState: LoadingState = .notStarted,
                get: @escaping Get)
    {
        self.storage = .init(initialState: initialState, get: get, set: null)
    }
    
    
    public init(_ initialValue: Value) {
        self.storage = .init(initialValue)
    }
    
    
    public init(_ initialValue: @escaping Get) {
        self.storage = .init(initialValue)
    }
}



@available(macOS 12, *)
@available(iOS 15, *)
public extension AsyncLazy {
    var wrappedValue: Value {
        get async {
            try! await storage.wrappedValue
        }
    }
    
    
    var loadingState: LoadingState {
        return storage.loadingState
    }
}
