//
//  onMainActor.swift
//  Homebrew App Store
//
//  Created by Ky on 2023-03-14.
//

import Foundation



/// Runs `action` on the main actor.
///
/// This is non-blocking; it returns immediately
///
/// - Parameter action: The action to run on the main actor
@inlinable
public func onMainActor(do action: @escaping @Sendable () -> Void) {
    Task {
        await MainActor.run(body: action)
    }
}
