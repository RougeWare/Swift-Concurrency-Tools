//
//  Mutex Tests.swift
//  ConcurrencyTools
//
//  Created by Ky directing Claude 4.6 Sonnet on 2026-02-26.
//
// Notes from Claude:
//  We test the public contract of Mutex<Value>:
//    - Values are stored and returned correctly
//    - Mutations persist across calls
//    - Concurrent access produces correct results (mutual exclusion)
//    - Errors are re-thrown and the lock is always released
//
//  Note: Because `run` accepts a *synchronous* closure, we cannot
//  hold the lock open across a suspension point from within a test.
//  The `noDataRace` test below is therefore our primary proof of mutual
//  exclusion — if exclusivity were broken, concurrent increments would
//  produce an incorrect total.
//

import Testing
import ConcurrencyTools



@Suite("Mutex")
struct MutexTests {
    
    // MARK: - Basic read / write
    
    @Test("Stores and returns the initial value")
    func initialValue() async {
        let box = Mutex(42)
        let result = await box.run { $0 }
        #expect(result == 42)
    }
    
    @Test("Mutations to the inout parameter are persisted")
    func mutation() async {
        let box = Mutex(0)
        await box.run { $0 = 99 }
        let result = await box.run { $0 }
        #expect(result == 99)
    }
    
    @Test("Returns whatever the closure produces")
    func returnValue() async {
        let box = Mutex("hello")
        let length = await box.run { $0.count }
        #expect(length == 5)
    }
    
    @Test("Works correctly with struct values")
    func structValue() async {
        struct Point: Sendable { var x, y: Int }
        let box = Mutex(Point(x: 1, y: 2))
        await box.run { $0.x += 10 }
        let result = await box.run { $0 }
        #expect(result.x == 11)
        #expect(result.y == 2)
    }
    
    // MARK: - Mutual exclusion
    
    /// This is the core proof of correctness. If two tasks could be inside `run` at the same time, some increments would be lost and the final count would be wrong.
    @Test("Concurrent increments always reach the correct total")
    func noDataRace() async {
        let counter = Mutex(0)
        let iterations = 500
        
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    await counter.run { $0 += 1 }
                }
            }
        }
        
        let final = await counter.run { $0 }
        #expect(final == iterations)
    }
    
    // MARK: - Error safety
    
    @Test("Lock is released even when the closure throws")
    func releasedOnThrow() async {
        struct BoomError: Error {}
        let box = Mutex(0)
        
        try? await box.run { _ in throw BoomError() }
        
        // If the lock were permanently held after a throw, this would hang.
        // The test runner's timeout will surface that if it happens.
        let acquired = await box.run { _ in true }
        #expect(acquired)
    }
    
    @Test("Errors thrown inside the closure are re-thrown to the caller")
    func errorPropagation() async {
        struct MyError: Error, Equatable {}
        let box = Mutex(0)
        
        do {
            try await box.run { _ in throw MyError() }
            Issue.record("Expected MyError to be thrown, but nothing was")
        } catch is MyError {
            // Correct path — reaching here is the assertion.
        } catch {
            Issue.record("Expected MyError but caught \(error)")
        }
    }
    
    // MARK: - Sequential correctness
    
    // Demonstrates that repeated acquire/release cycles leave the mutex
    // in a valid, re-enterable state each time.
    @Test("Multiple sequential calls all see up-to-date state")
    func sequentialCalls() async {
        let box = Mutex(0)
        for i in 1...10 {
            await box.run { $0 = i }
            let seen = await box.run { $0 }
            #expect(seen == i)
        }
    }
}
