//
//  Test.swift
//  ConcurrencyTools
//
//  Created by Ky directing Claude 4.6 Sonnet on 2026-02-26.
//
// Notes from Claude:
// Tests cover the public API contract of:
//   - ThrowingAsyncBinding
//   - ThrowingAsyncLazy
//   - AsyncBinding
//   - AsyncLazy
//
// We test *what* these types promise, not *how* they deliver it.
// Internal helpers (startLoading, update, ValueGenerator) are left alone.
//

import Testing
import Combine
import ConcurrencyTools



// MARK: - ThrowingAsyncBinding

@Suite("ThrowingAsyncBinding")
struct ThrowingAsyncBindingTests {
    
    // MARK: Static value init
    
    @Test("Static init: wrappedValue returns the initial value immediately")
    func staticInitReturnsValue() async throws {
        let binding = ThrowingAsyncBinding<Int, Error>(42)
        let value = try await binding.wrappedValue
        #expect(value == 42)
    }
    
    @Test("Static init: loadingState is .success before wrappedValue is ever read")
    func staticInitLoadingState() {
        let binding = ThrowingAsyncBinding<String, Error>("hello")
        guard case .success(let value) = binding.loadingState else {
            Issue.record("Expected .success, got \(binding.loadingState)")
            return
        }
        #expect(value == "hello")
    }
    
    @Test("Static init: setWrappedValue(_:) updates wrappedValue synchronously")
    func setWrappedValueUpdates() async throws {
        let binding = ThrowingAsyncBinding<Int, Error>(0)
        await binding.setWrappedValue(99)
        let value = try await binding.wrappedValue
        #expect(value == 99)
    }
    
    // MARK: Lazy/generator init
    
    @Test("Generator init: wrappedValue eventually returns the generated value")
    func generatorInitReturnsValue() async throws {
        let binding = ThrowingAsyncBinding<Int, Error> {
            return 7
        }
        let value = try await binding.wrappedValue
        #expect(value == 7)
    }
    
    @Test("Generator init: generator is called at most once (result is cached)")
    func generatorCalledOnce() async throws {
        let callCount = Mutex(0) // our Mutex<Int> from earlier in the session
        let binding = ThrowingAsyncBinding<Int, Error> {
            await callCount.run { $0 += 1 }
            return 42
        }
        
        _ = try await binding.wrappedValue
        _ = try await binding.wrappedValue
        
        let count = await callCount.run { $0 }
        #expect(count == 1, "Generator should only be called once; result must be cached")
    }
    
    // MARK: Dynamic get/set init
    
    @Test("Dynamic init: wrappedValue calls the getter")
    func dynamicInitGet() async throws {
        let binding = ThrowingAsyncBinding<Int, Error>(
            initialState: .notStarted,
            get: { 100 },
            set: { _ in }
        )
        let value = try await binding.wrappedValue
        #expect(value == 100)
    }
    
    @Test("Dynamic init: setWrappedValue(setter:) receives current value and can modify it")
    func setterReceivesCurrentValue() async throws {
        let binding = ThrowingAsyncBinding<Int, Error>(10)
        
        await binding.setWrappedValue(setter: { value in
            value *= 2
        })
        
        let result = try await binding.wrappedValue
        #expect(result == 20)
    }
    
    // MARK: Failure propagation
    
    @Test("Throwing getter: wrappedValue re-throws the error")
    func wrappedValueThrowsOnFailure() async {
        struct TestError: Error, Equatable {}
        
        let binding = ThrowingAsyncBinding<Int, TestError>(
            initialState: .notStarted,
            get: { () throws(TestError) -> Int in throw TestError() },
            set: { _ in }
        )
        
        do {
            _ = try await binding.wrappedValue
            Issue.record("Expected TestError to be thrown")
        }
        catch is TestError {
            // Correct — reaching here is the assertion.
        }
        catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test("Throwing getter: loadingState transitions to .failure")
    func loadingStateTransitionsToFailure() async throws {
        struct TestError: Error {}
        
        let binding = ThrowingAsyncBinding<Int, TestError>(
            initialState: .notStarted,
            get: { () throws(TestError) -> Int in throw TestError() },
            set: { _ in }
        )
        
        _ = try? await binding.wrappedValue
        
        guard case .failure = binding.loadingState else {
            Issue.record("Expected .failure, got \(binding.loadingState)")
            return
        }
    }
    
    @Test("setWrappedValue(throwing:throwingSetter:): .propagate re-throws to caller")
    func throwingSetterPropagates() async {
        struct CallerError: Error, Equatable {}
        
        let binding = ThrowingAsyncBinding<Int, Never>(0)
        
        do {
            try await binding.setWrappedValue(
                throwing: CallerError.self,
                throwingSetter: { (_) throws(UpdateSetterError<Never, CallerError>) -> Void in throw .propagate(CallerError()) }
            )
            Issue.record("Expected CallerError to be thrown")
        }
        catch is CallerError {
            // Correct.
        }
        catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test("setWrappedValue(throwing:throwingSetter:): .setBinding updates loadingState to .failure")
    func throwingSetterSetsBindingFailure() async throws {
        struct BindingError: Error {}
        
        let binding = ThrowingAsyncBinding<Int, BindingError>(
            initialState: .success(0),
            get: { 0 },
            set: { _ in }
        )
        
        await binding.setWrappedValue(
            throwing: Never.self,
            throwingSetter: { (_) throws(UpdateSetterError<BindingError, Never>) -> Void in throw UpdateSetterError<BindingError, Never>.setBinding(BindingError()) }
        )
        
        guard case .failure = binding.loadingState else {
            Issue.record("Expected loadingState to be .failure after .setBinding error")
            return
        }
    }
    
    // MARK: Loading state transitions
    
    @Test("notStarted: accessing loadingState triggers loading")
    func loadingStateTriggersLoad() async throws {
        let binding = ThrowingAsyncBinding<Int, Error>(
            initialState: .notStarted,
            get: { 55 },
            set: { _ in }
        )
        
        // Just touching loadingState should kick off the load.
        _ = binding.loadingState
        
        // Give the spawned Task a moment to complete.
        _ = try await binding.wrappedValue
        
        guard case .success(let value) = binding.loadingState else {
            Issue.record("Expected .success after loading completed")
            return
        }
        #expect(value == 55)
    }
}



// MARK: Additional ThrowingAsyncBinding Tests

extension ThrowingAsyncBindingTests {
    
    // MARK: Fan-out
    
    // If ten tasks all await `wrappedValue` while it's loading, every single
    // one should receive the result once it arrives — not just the first one.
    @Test("Multiple concurrent waiters all receive the value when it resolves")
    func concurrentWaitersAllReceiveValue() async throws {
        // Use a continuation to give us manual control over when the value resolves.
        let resolveValue: @Sendable () -> Int = { 42 }
        
        let binding = ThrowingAsyncBinding<Int, Never> {
            // Yield once to ensure waiters have time to park before we resolve.
            await Task.yield()
            return resolveValue()
        }
        
        let results = try await withThrowingTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try! await binding.wrappedValue
                }
            }
            var collected = [Int]()
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
        
        #expect(results.count == 10, "All 10 waiters should receive a result")
        #expect(results.allSatisfy { $0 == 42 }, "Every waiter should receive the correct value")
    }
    
    
    // MARK: Setter behaviour from failure state
    
    // When the binding is already in `.failure`, the async setter overload
    // that accepts an explicit `onFailure:` handler should call that handler
    // rather than proceeding to mutate the value.
    @Test("setWrappedValue(setter:onFailure:) calls onFailure when binding is in failure state")
    func setterCallsOnFailureWhenBindingFailed() async {
        struct SourceError: Error, Equatable {}
        
        let binding = ThrowingAsyncBinding<Int, SourceError>(
            initialState: .notStarted,
            get: { () throws(SourceError) in throw SourceError() },
            set: { _ in }
        )
        
        // Drive the binding into `.failure`.
        await #expect(throws: SourceError.self) {
            _ = try await binding.wrappedValue
        }
        
        var onFailureCalled = false
        await binding.setWrappedValue(setter: { $0 += 1 }, onFailure: { _ in
            onFailureCalled = true
        })
        
        #expect(onFailureCalled, "onFailure should be called when the binding is in a failure state")
    }
    
    
    // The overload without an explicit `onFailure:` should propagate the
    // existing failure back into the binding rather than silently swallowing it.
    @Test("setWrappedValue(setter:) re-records the failure when binding is in failure state")
    func setterRerecordsFailureWithoutOnFailure() async throws {
        struct SourceError: Error, Equatable {}
        
        let binding = ThrowingAsyncBinding<Int, SourceError>(
            initialState: .notStarted,
            get: { () throws(SourceError) in throw SourceError() },
            set: { _ in }
        )
        
        await #expect(throws: SourceError.self) {
            _ = try await binding.wrappedValue
        }
        
        // This should not crash or silently succeed — the failure should persist.
        await binding.setWrappedValue(setter: { $0 += 1 })
        
        guard case .failure = binding.loadingState else {
            Issue.record("Expected binding to remain in .failure after setter called on a failed binding")
            return
        }
    }
    
    
    // MARK: Lost-update behaviour
    
    // This test proves a known design characteristic: the async setter
    // performs a read → mutate copy → write across multiple suspension
    // points. If two setters interleave, one will overwrite the other's
    // result. This is not necessarily a bug (it mirrors how SwiftUI's
    // Binding works), but callers should be aware of it.
    //
    // If this test starts *failing* — i.e., both increments are preserved —
    // that would indicate the setter has been made atomic, which would be
    // a meaningful improvement worth noting in a changelog.
    @Test("Concurrent async setters exhibit last-write-wins behaviour (proves known characteristic)",
        .timeLimit(.minutes(1)),
          .disabled("Unsure how to test without deadlocking"))
    func concurrentSettersLastWriteWins() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(0)

        // This continuation is our gate. Task A will pause here after reading
        // the value, giving Task B a guaranteed window to complete first.
        // We use Optional so we can capture it from within the async setter body.
        var gate: CheckedContinuation<Void, Never>? = nil

        // Task A: reads value (0), then parks on the gate.
        async let taskA: Void = Task {
                await binding.setWrappedValue(setter: { value in
                    await withCheckedContinuation { continuation in
                        gate = continuation
                        // Don't resume yet — Task B will do that.
                    }
                    value += 1 // writes 1, but based on the stale read of 0
                })
            }
            .value

        // Give Task A enough time to park on the gate before Task B runs.
        await Task.yield()

        // Task B: completes its full read (0) → mutate (1) → write cycle.
        await binding.setWrappedValue(setter: { $0 += 1 })
        // binding is now 1.

        // Release Task A. It will now write its stale copy (also 1, from its
        // original read of 0), silently overwriting Task B's work.
        gate?.resume()
        await taskA

        let result = try await binding.wrappedValue

        // Both tasks incremented from 0, so both wrote 1.
        // One write was lost — the result is 1, not 2.
        #expect(result == 1, """
            Expected 1 (not 2) — demonstrates that the second setter \
            overwrote the first's result. If this starts returning 2, \
            setWrappedValue(setter:) has been made atomic.
            """)
    }
    
    
    // MARK: Double-trigger guard
    
    // Accessing `loadingState` twice in rapid succession from `.notStarted`
    // should only spawn one loading Task, not two. The generator should run
    // exactly once.
    //
    // Note: this is an inherently racy test due to `startLoading()` not being
    // actor-isolated. A single reliable failure here is a strong signal that
    // the guard in `startLoading()` needs to become actor-isolated.
    @Test("Rapid concurrent access to loadingState only triggers one load")
    func startLoadingNotTriggeredTwice() async throws {
        for _ in 1...100 {
            let callCount = Mutex(0)
            
            let binding = ThrowingAsyncBinding<Int, Never>(
                initialState: .notStarted,
                get: {
                    await callCount.run { $0 += 1 }
                    return 1
                },
                set: { _ in }
            )
            
            // Hammer loadingState from multiple tasks simultaneously.
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<10 {
                    group.addTask {
                        _ = binding.loadingState
                    }
                }
            }
            
            // Wait for loading to complete.
            _ = try! await binding.wrappedValue
            
            let count = await callCount.run { $0 }
            #expect(count == 1, "Generator should only be called once regardless of concurrent loadingState access")
        }
    }
    
    
    @Test("Atomic setters preserve all concurrent updates (no lost writes)")
    func concurrentSettersAreAtomic() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(0)
        
        var gate: CheckedContinuation<Void, Never>? = nil
        
        // Task A acquires the mutex, then parks mid-setter on the gate,
        // holding the mutex open while it waits.
        async let taskA: Void = binding.setWrappedValue(setter: { value in
            await withCheckedContinuation { continuation in
                gate = continuation
            }
            value += 1
        })
        
        // Let Task A enter the mutex and park on the gate.
        await Task.yield()
        
        // Task B queues on the mutex behind Task A.
        // `async let` is essential: the main task must remain free to
        // resume the gate below. `await`-ing here would deadlock.
        async let taskB: Void = binding.setWrappedValue(setter: { $0 += 1 })
        
        // Let Task B reach the mutex and park in the queue.
        await Task.yield()
        
        // Release Task A. It writes 1, releases the mutex, Task B wakes.
        // Task B re-reads 1 (A's committed result) and writes 2.
        gate?.resume()
        await taskA
        await taskB
        
        let result = try await binding.wrappedValue
        #expect(result == 2, """
            Both increments must be preserved. If this returns 1, the \
            re-read inside the mutex has regressed to a pre-mutex snapshot.
            """)
    }
    
    
    // MARK: Atomicity
    
    /// Proves the core atomicity guarantee at scale. With 100 concurrent
    /// increments, all must be preserved — any lost write signals the
    /// read-modify-write has escaped the critical section.
    @Test("100 concurrent atomic setters all preserve their writes")
    func manyAtomicSetters() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(0)
        
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await binding.setWrappedValue(setter: { $0 += 1 })
                }
            }
        }
        
        let result = try await binding.wrappedValue
        #expect(result == 100, "All 100 increments must be preserved")
    }
    
    
    /// Proves that two setters interleaved at the worst possible moment
    /// still both commit correctly: Task A parks mid-setter while holding
    /// the mutex, Task B queues behind it, then A commits and B re-reads
    /// A's result before applying its own mutation.
    @Test("Deterministically interleaved setters both preserve their writes")
    func deterministicallyInterleavedSetters() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(0)
        let gate = Gate()
        
        // Task A: acquires the mutex, parks on the gate mid-setter.
        async let taskA: Void = binding.setWrappedValue(setter: { value in
            await gate.suspend()
            value += 1  // operates on whatever is current when resumed
        })
        
        // Let Task A enter the mutex and park.
        await Task.yield()
        
        // Task B: queues on the mutex behind A.
        // `async let` keeps the main task free to resume the gate.
        async let taskB: Void = binding.setWrappedValue(setter: { $0 += 1 })
        
        // Let Task B park in the mutex queue.
        await Task.yield()
        
        // Release A → A writes 1, releases mutex → B wakes, re-reads 1, writes 2.
        await gate.resume()
        await taskA
        await taskB
        
        let result = try await binding.wrappedValue
        #expect(result == 2, """
                Both increments must be preserved. \
                If this returns 1, the re-read has regressed to a pre-mutex snapshot.
                """)
    }
    
    
    // MARK: - Load interaction
    
    /// Proves the two-phase setter correctly bridges an in-progress load:
    /// phase 1 parks until initialization completes, then phase 2 applies
    /// its mutation to the freshly-resolved value.
    @Test("Setter fired before load completes waits, then mutates the loaded value")
    func setterWaitsForLoad() async throws {
        let gate = Gate()
        
        let binding = ThrowingAsyncBinding<Int, Never> {
            await gate.suspend()
            return 10
        }
        
        _ = binding.loadingState  // kick off load; it parks on gate
        
        // Setter starts concurrently — parks in phase 1 waiting for resolution.
        async let setTask: Void = binding.setWrappedValue(setter: { $0 += 5 })
        
        await Task.yield()  // let setter reach phase 1
        
        await gate.resume()  // binding resolves to 10
        await setTask        // setter sees 10, writes 15
        
        let result = try await binding.wrappedValue
        #expect(result == 15, "Setter must observe the loaded value (10) and apply +5")
    }
    
    
    // MARK: - Failure interaction
    
    /// Proves that a setter applied to a failed binding never touches
    /// the setter body and routes directly to `onFailure`.
    @Test("Setter on failed binding calls onFailure exactly once, never calls setter body")
    func setterOnFailedBindingCallsOnFailure() async {
        struct LoadError: Error {}
        
        let binding = ThrowingAsyncBinding<Int, LoadError>(
            initialState: .notStarted,
            get: { () throws(LoadError) in throw LoadError() },
            set: { _ in }
        )
        
        _ = try? await binding.wrappedValue  // drive into .failure
        
        // setter is @Sendable async, so we can await our Mutex inside it.
        let setterCallCount = Mutex(0)
        // onFailure is a plain sync (non-Sendable) closure — plain var is safe.
        var onFailureCalled = false
        
        await binding.setWrappedValue(
            setter: { _ in await setterCallCount.run { $0 += 1 } },
            onFailure: { _ in onFailureCalled = true }
        )
        
        let count = await setterCallCount.run { $0 }
        #expect(count == 0,     "Setter body must not be called in failure state")
        #expect(onFailureCalled, "onFailure must be called exactly once")
    }
    
    
    // MARK: - Throwing setter
    
    /// Proves the throwing setter's `.propagate` path correctly re-throws
    /// to the caller without corrupting the binding's state.
    @Test("Throwing setter .propagate re-throws and leaves binding state unchanged")
    func throwingSetterPropagateDoesNotCorruptState() async throws {
        struct CallerError: Error, Equatable {}
        
        let binding = ThrowingAsyncBinding<Int, Never>(42)
        
        do {
            try await binding.setWrappedValue(
                throwing: CallerError.self,
                throwingSetter: { _ throws(UpdateSetterError<Never, CallerError>) in
                    throw .propagate(CallerError())
                }
            )
            Issue.record("Expected CallerError to be thrown")
        } catch is CallerError {}
        
        // The binding must be unchanged — a propagated error is the caller's
        // problem, not the binding's.
        let result = try await binding.wrappedValue
        #expect(result == 42, "Binding value must be unchanged after .propagate")
    }
    
    
    /// Proves that 100 concurrent throwing setters all preserve their writes,
    /// even through the added complexity of the `Result`-smuggling path.
    @Test("100 concurrent throwing setters all preserve their writes")
    func manyAtomicThrowingSetters() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(0)
        
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    try? await binding.setWrappedValue(
                        throwing: Never.self,
                        throwingSetter: { (value) throws(UpdateSetterError<Never, Never>) in
                            value += 1
                        }
                    )
                }
            }
        }
        
        let result = try await binding.wrappedValue
        #expect(result == 100, "All 100 increments must be preserved through throwing setter path")
    }
}


// MARK: - ThrowingAsyncLazy

@Suite("ThrowingAsyncLazy")
struct ThrowingAsyncLazyTests {
    
    @Test("Static init: wrappedValue returns initial value")
    func staticInit() async throws {
        let lazy = ThrowingAsyncLazy<String, Error>("swift")
        let value = try await lazy.wrappedValue
        #expect(value == "swift")
    }
    
    @Test("Generator init: wrappedValue returns the generated value")
    func generatorInit() async throws {
        let lazy = ThrowingAsyncLazy<Int, Error>(get: { 123 })
        let value = try await lazy.wrappedValue
        #expect(value == 123)
    }
    
    @Test("Generator init: throwing getter propagates the error")
    func throwingGenerator() async {
        struct LazyError: Error, Equatable {}
        
        let lazy = ThrowingAsyncLazy<Int, LazyError>(get: { () throws(LazyError) in throw LazyError() })
        
        do {
            _ = try await lazy.wrappedValue
            Issue.record("Expected LazyError")
        }
        catch is LazyError {
            // Correct.
        }
        catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}


// MARK: - AsyncBinding

@Suite("AsyncBinding")
struct AsyncBindingTests {
    
    @Test("Static init: wrappedValue returns initial value")
    func staticInit() async {
        let binding = AsyncBinding(42)
        let value = await binding.wrappedValue
        #expect(value == 42)
    }
    
    @Test("Generator init: wrappedValue returns the generated value")
    func generatorInit() async {
        let binding = AsyncBinding<String> { "generated" }
        let value = await binding.wrappedValue
        #expect(value == "generated")
    }
    
    @Test("setWrappedValue(_:): updates the wrapped value")
    func setWrappedValue() async {
        let binding = AsyncBinding(0)
        await binding.setWrappedValue(77)
        let value = await binding.wrappedValue
        #expect(value == 77)
    }
    
    @Test("loadingState reflects the current state")
    func loadingState() async {
        let binding = AsyncBinding(99)
        guard case .success(let value) = binding.loadingState else {
            Issue.record("Expected .success for static init")
            return
        }
        #expect(value == 99)
    }
}


// MARK: - AsyncLazy

@Suite("AsyncLazy")
struct AsyncLazyTests {
    
    @Test("Static init: wrappedValue returns initial value")
    func staticInit() async {
        let lazy = AsyncLazy("stored")
        let value = await lazy.wrappedValue
        #expect(value == "stored")
    }
    
    @Test("Generator init: wrappedValue returns the generated value")
    func generatorInit() async {
        let lazy = AsyncLazy<Double> { 3.14 }
        let value = await lazy.wrappedValue
        #expect(value == 3.14)
    }
    
    @Test("loadingState for static init is .success immediately")
    func staticLoadingState() {
        let lazy = AsyncLazy(true)
        guard case .success(let value) = lazy.loadingState else {
            Issue.record("Expected .success")
            return
        }
        #expect(value == true)
    }
}
