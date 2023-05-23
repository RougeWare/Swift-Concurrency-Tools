//
//  resync Tests.swift
//  
//
//  Created by Northstar✨System on 2023-05-22.
//

import XCTest
import ConcurrencyTools



final class resync_Tests: XCTestCase {

    func testResync() throws {
        XCTAssertNoThrow(try resync(TestActor.default.int))
        XCTAssertNoThrow(resync(TestActor.default.int_nothrow))
    }
}
