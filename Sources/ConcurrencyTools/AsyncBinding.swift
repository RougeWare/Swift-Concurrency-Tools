//
//  AsyncBinding.swift
//  Generic App HOSTESS Testbed
//
//  Created by Ky on 2026-01-24.
//

@preconcurrency import Combine
import SwiftUI

import FunctionTools
@preconcurrency import SafePointer



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



// MARK: - ThrowingAsyncBinding

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
        self.init(subject: Subject(.loading),
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
    @MainActor
    var wrappedValue: Value {
        get async throws(Failure) {
            // If we already have a terminal state, return it immediately
            switch loadingState {
            case let .success(value):
                return value
                
            case let .failure(error):
                throw error
                
            case .notStarted, .loading:
                // Otherwise wait for a terminal state
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
    
    
    var loadingState: LoadingState {
        startLoading()
        return subject.value
    }
}



// MARK: API - set

@available(macOS 12, *)
@available(iOS 15, *)
public extension ThrowingAsyncBinding {
    nonmutating func setWrappedValue<Thrown: Error>(
        throwing _: Thrown.Type = Thrown.self,
        throwingSetter: ThrowingSetWrappedValue<Thrown>,
        onFailure: (Failure) -> Void)
    async throws(Thrown) {
        var copy: Value
        
        do {
            copy = try await self.wrappedValue
        }
        catch {
            return onFailure(error)
        }
        
        do {
            try await throwingSetter(&copy)
        }
        catch let error {
            switch error {
            case .setBinding(let failure):
                self.update(toFailure: failure)
                
            case .propagate(let error):
                throw error
            }
        }
        
        self.update(toValue: copy)
    }
    
    
    nonmutating func setWrappedValue<Thrown: Error>(
        throwing _: Thrown.Type = Thrown.self,
        throwingSetter: ThrowingSetWrappedValue<Thrown>)
    async throws(Thrown) {
        try await setWrappedValue(
            throwing: Thrown.self,
            throwingSetter: throwingSetter,
            onFailure: update(toFailure:))
    }
    
    
    nonmutating func setWrappedValue(setter: SetWrappedValue, onFailure: (Failure) -> Void) async {
        var copy: Value
        
        do {
            copy = try await self.wrappedValue
        }
        catch {
            return onFailure(error)
        }
        
        await setter(&copy)
        
        self.update(toValue: copy)
    }
    
    
    nonmutating func setWrappedValue(setter: SetWrappedValue) async {
        await setWrappedValue(setter: setter, onFailure: update(toFailure:))
    }
    
    
    nonmutating func setWrappedValue(_ newValue: Value) {
        update(toValue: newValue)
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
            update(generateValue)
        }
    }
    
    
    private func update(_ block: @escaping Get) {
        subject.send(.loading)
        Task {
            do {
                update(toValue: try await block())
            }
            catch let error as Failure {
                update(toFailure: error)
            }
            catch {
                preconditionFailure("The compiler should always ensure that thrown errors here are `Failure`s")
            }
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
