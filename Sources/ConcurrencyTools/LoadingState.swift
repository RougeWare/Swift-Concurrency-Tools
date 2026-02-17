//
//  LoadingState.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-02-17.
//



// MARK: - LoadingState

/// Describes the current state of loading something.
public enum LoadingState<Value>: Sendable
where Value: Sendable
{
    /// Nothing has yet attempted to start loading the value
    case notStarted
    
    /// The value is currently loading
    case loading
    
    /// The value was successfulyl loaded, and stored in this case
    case success(Value)
}



// MARK: Equatable

extension LoadingState: Equatable where Value : Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted),
            (.loading, .loading):
            return true

        case (.success(let lhsValue), .success(let rhsValue)):
            return lhsValue == rhsValue

        case (.notStarted, _),
            (.loading, _),
            (.success, _):
            return false
        }
    }
}



// MARK: - FailableLoadingState

/// Describes the current state of loading something which might fail to load.
///
/// You might think of this similarly to `Result`, but with additional cases describing the current loading state if it's not yet resolved.
public enum FailableLoadingState<Success, Failure>: Sendable
where Success: Sendable,
      Failure: Error,
      Failure: Sendable
{
    /// Nothing has yet attempted to start loading the value
    case notStarted
    
    /// The value is currently loading
    case loading
    
    /// The value was successfulyl loaded, and stored in this case
    case success(Success)
    
    /// The value failed to be loaded, and an error describing that failure is stored in this case
    case failure(Failure)
    
    
    /// Losslessly convert the given ``Result`` to a ``FailableLoadingState``
    public init(_ result: Result<Success, Failure>) {
        switch result {
        case .success(let value):
            self = .success(value)
        case .failure(let error):
            self = .failure(error)
        }
    }
}
