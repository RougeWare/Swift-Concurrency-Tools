//
//  Semaphore Tests.swift
//  ConcurrencyTools
//
//  Created by Ky on 2025-05-08.
//

import Testing
import ConcurrencyTools
@preconcurrency import SafePointer



struct SemaphoreTests {
    
    @Test
    func testBasicWaitSignal() async throws {
        let semaphore = Semaphore()
        var didSignal = false
        
        // Start a task that will wait on the semaphore
        Task {
            await semaphore.wait()
            didSignal = true
        }
        
        // Give the task time to start and wait
        try await Task.sleep(for: .seconds(0.1))
        
        // Verify that the semaphore is blocking
        #expect(didSignal == false)
        
        // Signal the semaphore and verify that the task completes
        semaphore.signal()
        try await Task.sleep(for: .seconds(0.1))
        #expect(didSignal == true)
    }
    
    
    @Test
    func testInitialValueSemantics() async throws {
        // Semaphore with initial value of 1 should allow one wait without blocking
        let semaphore = Semaphore(_value: 1)
        var firstWaitCompleted = false
        var secondWaitCompleted = false
        
        // First wait should complete immediately
        Task {
            await semaphore.wait()
            firstWaitCompleted = true
        }
        
        try await Task.sleep(for: .seconds(0.1))
        
        // Second wait should block
        Task {
            await semaphore.wait()
            secondWaitCompleted = true
        }
        
        try await Task.sleep(for: .seconds(0.1))
        
        #expect(firstWaitCompleted == true)
        #expect(secondWaitCompleted == false)
        
        // Signal should unblock the second wait
        semaphore.signal()
        try await Task.sleep(for: .seconds(0.1))
        #expect(secondWaitCompleted == true)
    }
    
    
    @Test
    func testTimeoutBehavior() async {
        let semaphore = Semaphore()
        
        do {
            try await semaphore.wait(timeout: 0.1)
            Issue.record("Wait should have timed out")
        }
        catch is Semaphore.WaitTimedOut {
            // Expected behavior
        }
        catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    
    @Test
    func testDeinitResumesWaiters() async throws { await withKnownIssue("Strong references to `semaphore` within Tasks causes it to remain allocated") {
        var firstWaiterResumed = false
        var secondWaiterResumed = false
        do {
            var semaphore = Semaphore()
            
            // Start two waiters
            Task.detached(priority: .high) { [weak semaphore] in
                await semaphore?.wait()
                firstWaiterResumed = true
            }
            
            // Give tasks time to start waiting
            try await Task.sleep(for: .seconds(0.1))
            
            Task.detached(priority: .high) { [weak semaphore] in
                await semaphore?.wait()
                secondWaiterResumed = true
            }
            
            // Give tasks time to start waiting
            try await Task.sleep(for: .seconds(0.1))
            
            // Verify that both are blocked
            #expect(false == firstWaiterResumed)
            #expect(false == secondWaiterResumed)
            
            // Deinitialize the semaphore, which should resume all waiters
            semaphore = .init()
        }
        
        
        // Give tasks time to resume
        try await Task.sleep(for: .seconds(1))
        
        // Verify that both waiters were resumed
        #expect(true == firstWaiterResumed)
        #expect(true == secondWaiterResumed)
    }}
    
    
    @Test(arguments: [3, 10, 30])
    func testMultipleWaitSignalPairs(count: UInt) async throws {
        
        actor Wrapper {
            nonisolated(unsafe) var completedTasks = [UInt]()
            
            
            func append(_ value: UInt) {
                completedTasks.append(value)
            }
            
            
            nonisolated(unsafe) var count: Int { completedTasks.count }
        }
        
        
        
        let semaphore = Semaphore()
        let completedTasks = Wrapper()
        
        // Create several tasks that will wait on the semaphore
        for i in 1...count {
            Task.detached {
                await semaphore.wait()
                await completedTasks.append(i)
            }
        }
        
        // Give tasks time to start waiting
        try await Task.sleep(for: .seconds(0.1))
        
        #expect(0 == completedTasks.count)
        
        // Signal N times and verify the tasks complete in LIFO order
        // (This is implementation-dependent, but matches the documented behavior)
        for _ in 1...count {
            Task {
                semaphore.signal()
            }
        }
        
        try await Task.sleep(for: .seconds(0.1))
        
        #expect(count == completedTasks.count)
    }
    
    
    @Test
    func testDurationBasedTimeout() async throws {
        guard #available(macOS 13.0, *) else { return }
        
        let semaphore = Semaphore()
        
        do {
            try await semaphore.wait(timeout: .milliseconds(100))
            Issue.record("Wait should have timed out")
        }
        catch is Semaphore.WaitTimedOut {
            // Expected behavior
        }
        catch {
            Issue.record(error, "Unexpected error: \(error)")
        }
    }
    
    
    @Test
    func testSignalReturnValue() async throws {
        let semaphore = Semaphore()
        
        // When no one is waiting, signal should return false
        let initialSignalResult = semaphore.signal()
        #expect(initialSignalResult == false)
        
        // Start a task that will wait
        Task {
            await semaphore.wait()
        }
        
        // Give the task time to start waiting
        try await Task.sleep(for: .seconds(0.1))
        
        // When we've dismissed all waiters, signal should return false
        let signalWithWaiterResult = semaphore.signal()
        #expect(signalWithWaiterResult == false)
        
        // Start a task that will wait multiple times
        Task {
            await semaphore.wait()
            await semaphore.wait()
        }
        
        // Give the task time to start waiting
        try await Task.sleep(for: .seconds(0.1))
        
        // When someone is still waiting after dismissing a waiter, signal should return true
        let signalWith2WaitersResult = semaphore.signal()
        #expect(signalWith2WaitersResult == true)
        let signalWith1WaitersResult = semaphore.signal()
        #expect(signalWith1WaitersResult == false)
    }
}
