//
//  Array + sugar.swift
//  ConcurrencyTools
//
//  Created by Ky on 2026-05-12.
//

import Foundation



public extension Array {
    mutating func popFirst() -> Element? {
        guard !isEmpty else { return nil }
        return removeFirst()
    }
}
