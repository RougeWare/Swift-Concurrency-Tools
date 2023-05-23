//
//  DispatchSemaphore + sugar.swift
//  Plural Diagramming
//
//  Created by The Northstar✨ System on 2023-01-17.
//

import Foundation



public extension DispatchSemaphore {
    static var `default`: Self {
        Self.init(value: 0)
    }
}
