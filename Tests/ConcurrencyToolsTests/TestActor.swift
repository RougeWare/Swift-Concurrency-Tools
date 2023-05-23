//
//  TestActor.swift
//  
//
//  Created by Northstar✨System on 2023-05-22.
//

import XCTest



actor TestActor {
    
    @Sendable
    func int_nothrow() async -> Int {
        await int_nothrow(sleepSeconds: .init(Self.defaultSleepTime))
    }
    
    
    @Sendable
    func int_nothrow(sleepSeconds: UInt8) async -> Int {
        await Task.detached(priority: .low) {
            do {
                try await Task.sleep(seconds: .init(sleepSeconds))
            }
            catch {
                XCTFail("Couldn't sleep: \(error)")
            }
            
            return Int.random(in: .min ... .max)
        }
        .value
    }
    
    
    @Sendable
    func int() async throws -> Int {
        try await int(sleepSeconds: .init(Self.defaultSleepTime))
    }
    
    
    @Sendable
    func int(sleepSeconds: UInt8) async throws -> Int {
        try await Task.detached(priority: .low) {
            do {
                try await Task.sleep(seconds: .init(sleepSeconds))
            }
            catch {
                print("Couldn't sleep:", error)
                throw error
            }
            
            return Int.random(in: .min ... .max)
        }
        .value
    }
}



extension TestActor {
    static var `default` = TestActor()
    
    static let defaultSleepTime: TimeInterval = 2
}
