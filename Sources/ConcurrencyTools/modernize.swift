//
//  modernize.swift
//  ConcurrencyTools
//
//  Created by Ky on 2024-11-22.
//

import Foundation

import FunctionTools



public func modernize<Success: Sendable, Failure: Error>(callback: Callback<Callback<Result<Success, Failure>>>) async throws(Failure) -> Success {
    do {
        return try await withCheckedThrowingContinuation { continuation in
            callback { result in
                switch result {
                case .success(let success):
                    continuation.resume(returning: success)
                    
                case .failure(let failure):
                    continuation.resume(throwing: failure)
                }
            }
        }
    }
    catch {
        throw error as! Failure
    }
}



public func modernize<Value: Sendable>(callback: Callback<Callback<Value>>) async -> Value {
    await withCheckedContinuation { continuation in
        callback { value in
            continuation.resume(returning: value)
        }
    }
}
