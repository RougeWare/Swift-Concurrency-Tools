//
//  desync Tests.swift
//  
//
//  Created by Northstar✨System on 2023-05-22.
//

import XCTest
import ConcurrencyTools

final class desync_Tests: XCTestCase {

    func testDesync() throws {
        print(Date())
        defer { print(Date()) }
        
        let semaphore = DispatchSemaphore.default
        
        var didFinishDesyncCallback = false
        
        desync(task: TestActor.default.int) { result in
            defer {
                semaphore.signal()
                didFinishDesyncCallback = true
            }
            
            switch result {
            case .success(let success):
                print("desync successfully got `\(success)`")
            case .failure(let failure):
                print("desync successfully caught this error: \(failure)")
            }
        }
        
        let timeoutResult = semaphore.wait(timeout: .now() + (TestActor.defaultSleepTime * 5))
        
        switch timeoutResult {
        case .success:
            print("desync success")
            
        case .timedOut:
            XCTFail("desync didn't finish in time")
        }
        
        if !didFinishDesyncCallback {
            XCTFail("desync never reached end of callback block")
        }
    }
}
