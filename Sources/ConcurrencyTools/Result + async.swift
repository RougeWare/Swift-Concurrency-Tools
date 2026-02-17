//
//  Result + async.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-02-17.
//

import Foundation



public extension Result {
    
    /// Creates a new result by evaluating a throwing async closure, capturing the returned value as a success, or any thrown error as a failure.
    ///
    /// - Parameter body: A potentially throwing closure to evaluate.
    init(catching body: () async throws(Failure) -> Success) async {
        do {
            self = .success(try await body())
        }
        catch {
            self = .failure(error)
        }
    }
}
