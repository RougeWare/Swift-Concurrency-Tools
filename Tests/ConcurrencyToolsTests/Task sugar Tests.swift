//
//  Task sugar Tests.swift
//  
//
//  Created by Northstar✨System on 2023-05-22.
//

import XCTest
import ConcurrencyTools
import SafePointer



final class Task_sugar_Ttests: XCTestCase {

    func testSleep_seconds() throws {
        
        let sleepSeconds = TimeInterval.random(in: 2 ..< 4)
        
        let before = MutableSafePointer(to: Date.distantPast)
        let after = MutableSafePointer(to: Date.distantFuture)
        
        try resync {
            before.pointee = Date()
            try await Task.sleep(seconds: sleepSeconds)
            after.pointee = Date()
        }
        
        XCTAssertEqual(after.pointee.timeIntervalSince(before.pointee), sleepSeconds,
                       accuracy: 1)
    }
}
