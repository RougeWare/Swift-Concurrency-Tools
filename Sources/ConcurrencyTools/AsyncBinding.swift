//
//  AsyncBinding.swift
//  Generic App HOSTESS Testbed
//
//  Created by Ky on 2026-01-24.
//

@preconcurrency import Combine
import SwiftUI

import FunctionTools



// MARK: - ThrowingAsyncLazy

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
    public typealias Subject = CurrentValueSubject<LoadingState, Never>
    
    
    
    private let subject: Subject
    private var valueGenerator: ValueGenerator
    
    
    public init(initialState: LoadingState = .notStarted,
                get: @escaping Get,
                set: @escaping Set) {
        self.subject = Subject(initialState)
        self.valueGenerator = .dynamic(getter: get, setter: set)
    }
    
    
    public init(_ initialValue: Value) {
        let initialValue = Result.success(initialValue)
        self.subject = Subject(.init(initialValue))
        self.valueGenerator = .static(initialValue)
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
        throwingSetter: (inout Value) async throws(UpdateSetterError<Thrown>) -> Void,
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
        throwingSetter: (inout Value) async throws(UpdateSetterError<Thrown>) -> Void)
    async throws(Thrown) {
        try await setWrappedValue(
            throwing: Thrown.self,
            throwingSetter: throwingSetter,
            onFailure: update(toFailure:))
    }
    
    
    nonmutating func setWrappedValue(setter: (inout Value) async -> Void, onFailure: (Failure) -> Void) async {
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
    
    
    nonmutating func setWrappedValue(setter: (inout Value) async -> Void) async {
        await setWrappedValue(setter: setter, onFailure: update(toFailure:))
    }
    
    
    nonmutating func setWrappedValue(_ newValue: Value) {
        update(toValue: newValue)
    }
    
    
    
    typealias UpdateSetterError<ThrownError: Error & Sendable> = ConcurrencyTools.UpdateSetterError<Failure, ThrownError>
}



/// An error which might happen within the update setter block
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
        }
    }
}



// MARK: Storage

@available(macOS 12, *)
@available(iOS 15, *)
private extension ThrowingAsyncBinding {
    enum ValueGenerator: Sendable {
        case `static`(Result)
        case dynamic(getter: Get, setter: Set)
    }
}



// MARK: FailableLoadingState

public enum FailableLoadingState<Success, Failure>: Sendable
where Success: Sendable,
      Failure: Error,
      Failure: Sendable
{
    case notStarted
    case loading
    case success(Success)
    case failure(Failure)
    
    
    init(_ result: Result<Success, Failure>) {
        switch result {
        case .success(let value):
            self = .success(value)
        case .failure(let error):
            self = .failure(error)
        }
    }
}



// MARK: - AsyncBinding

//public struct AsyncBinding<Value>: Sendable
//where Value: Sendable
//{
//    
//    public typealias LoadingState = Generic_App_HOSTESS_Testbed.LoadingState<Value>
//    public typealias AsyncBindingGet = @Sendable () async -> Value
//    public typealias AsyncBindingSet = @Sendable (Value) async -> Void
//    
//    
//    
//    private let subject: CurrentValueSubject<LoadingState, Never>
//    private var storage: Storage
//    
//    
//    public init(initialState: LoadingState = .notStarted,
//                get: @escaping AsyncBindingGet,
//                set: @escaping AsyncBindingSet) {
//        self.subject = CurrentValueSubject(initialState)
//        self.storage = .dynamic(getter: get, setter: set)
//    }
//    
//    
//    public init(_ initialValue: Value) {
//        self.subject = CurrentValueSubject(.success(initialValue))
//        self.storage = .static(initialValue)
//    }
//    
//    
//    private func startLoading() {
//        switch subject.value {
//        case .loading,
//                .success(_):
//            return
//            
//        case .notStarted:
//            update(getValue)
//        }
//    }
//    
//    
//    /// Suspends until the value is successfully loaded or an error occurs.
//    ///
//    /// If a success or failure already exists, then this returns/throws immediately. Otherwise, this pauses until one of those is reached.
//    ///
//    /// - Returns: The bound value
//    /// - Throws: Any error that occurred trying to get the bound value
//    @MainActor
//    public var wrappedValue: Value {
//        get async {
//            startLoading()
//            
//            // If we already have a terminal state, return it immediately
//            switch loadingState {
//            case let .success(value):
//                return value
//                
//            case .notStarted, .loading:
//                // Otherwise wait for a terminal state
//                for await state in subject.values {
//                    switch state {
//                    case .notStarted, .loading:
//                        // Since the `subject` isn't actually a specific collection, but instead a data stream of this binding's loading state, we "loop" until it's something we can use. Keep in mind the loop pauses automatically when there's no new values, so this isn't a spinlock
//                        continue
//                        
//                    case .success(let value):
//                        return value
//                    }
//                }
//                
//                // `CurrentValueSubject<LoadingState, Never>`'s `.values` sequence can Never terminate.
//                // This whole object will be deallocated before that, killing the loop before it gets to this fatal error.
//                preconditionFailure("Unexpected terminal state in AsyncBinding.wrappedValue")
//            }
//        }
//    }
//    
//    
//    public var loadingState: LoadingState {
//        startLoading()
//        return subject.value
//    }
//    
//    
//    private func update(_ block: @escaping AsyncBindingGet) {
//        subject.send(.loading)
//        Task {
//            let value = await block()
//            subject.send(.success(value))
//        }
//    }
//    
//    
//    private func getValue() async -> Value {
//        switch storage {
//        case .dynamic(getter: let getter, setter: _):
//            return await getter()
//            
//        case .static(let value):
//            return value
//        }
//    }
//}
//
//
//
//public extension AsyncBinding {
//    enum Storage: Sendable {
//        case `static`(Value)
//        case dynamic(getter: AsyncBindingGet, setter: AsyncBindingSet)
//    }
//}
//
//
//
//public enum LoadingState<Success>: Sendable
//where Success: Sendable
//{
//    case notStarted
//    case loading
//    case success(Success)
//}



//extension LoadingState: Equatable where Value : Equatable {
//    public static func == (lhs: Self, rhs: Self) -> Bool {
//        switch (lhs, rhs) {
//        case (.notStarted, .notStarted),
//            (.loading, .loading):
//            return true
//            
//        case (.success(let lhsValue), .success(let rhsValue)):
//            return lhsValue == rhsValue
//            
//        case (.failure(let lhsError), .failure(let rhsError)):
//            return (lhsError as NSError) == (rhsError as NSError)
//            
//        case (.notStarted, _),
//            (.loading, _),
//            (.success, _),
//            (.failure, _):
//            return false
//        }
//    }
//}
