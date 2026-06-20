//
//  LoadingState.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-02-17.
//



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
    
    
    /// Losslessly convert the given non-failing ``FailableLoadingState`` into a ``LoadingState``
    public init(_ failableLoadingState: FailableLoadingState<Value, Never>) {
        switch failableLoadingState {
        case .notStarted:         self = .notStarted
        case .loading:            self = .loading
        case .success(let value): self = .success(value)
        // case .failure(_) actually doesn't need to be here because its only possible associated value is `Never`! Cool!
        }
    }
}



// MARK: Equatable

extension LoadingState: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted),
            (.loading, .loading):
            return true

        case (.success(let lhsValue), .success(let rhsValue)):
            return lhsValue == rhsValue

        case (.notStarted, _),
            (.loading, _),
            (.success(_), _):
            return false
        }
    }
}
