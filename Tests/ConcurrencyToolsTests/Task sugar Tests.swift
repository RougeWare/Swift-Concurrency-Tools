//
//  Task sugar Tests.swift
//  
//
//  Created by Northstar✨System on 2023-05-22.
//

import XCTest
import ConcurrencyTools

final class Task_sugar_Ttests: XCTestCase {

    func testSleep_seconds() throws {
        
        let sleepSeconds = TimeInterval.random(in: 2 ..< 4)
        
        var before = Date()
        var after = Date()
        
        try resync {
            before = Date()
            try await Task.sleep(seconds: sleepSeconds)
            after = Date()
        }
        
        XCTAssertEqual(after.timeIntervalSince(before), sleepSeconds,
                       accuracy: 1)
    }
}
