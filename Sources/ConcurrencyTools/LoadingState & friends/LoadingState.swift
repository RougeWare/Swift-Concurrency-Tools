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
