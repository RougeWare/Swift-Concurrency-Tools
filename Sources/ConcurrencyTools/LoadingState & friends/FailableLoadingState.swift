//
//  FailableLoadingState.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-02-17.
//



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



// MARK: Equatable

extension FailableLoadingState: Equatable
where Success: Equatable,
      Failure: Equatable
{
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted),
            (.loading, .loading):
            return true

        case (.success(let lhsValue), .success(let rhsValue)):
            return lhsValue == rhsValue
            
        case (.failure(let lhsError), .failure(let rhsError)):
            return lhsError == rhsError

        case (.notStarted, _),
            (.loading, _),
            (.success(_), _),
            (.failure(_), _):
            return false
        }
    }
}
