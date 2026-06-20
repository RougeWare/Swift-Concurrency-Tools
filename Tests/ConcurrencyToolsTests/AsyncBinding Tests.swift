//
//  AsyncBinding Tests.swift
//  ConcurrencyTools
//
//  Created by Ky directing Claude 4.7 Opus on 2026-05-14.
//
//  Tests cover the public API contract of:
//    - ThrowingAsyncBinding
//    - ThrowingAsyncLazy
//    - AsyncBinding
//    - AsyncLazy
//
//  We test *what* these types promise, not *how* they deliver it.
//  Internal helpers (startLoading, update, ValueGenerator) are left alone.
//

import Testing
import ConcurrencyTools



// MARK: - ThrowingAsyncBinding

@Suite("ThrowingAsyncBinding")
struct ThrowingAsyncBindingTests {
    
    // MARK: Static value init
    
    @Test("Static init: wrappedValue returns the initial value")
    func staticInitWrappedValue() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(42)
        let value = try await binding.wrappedValue
        #expect(value == 42)
    }
    
    
    @Test("Static init: loadingState is .success immediately, before any read")
    func staticInitLoadingState() {
        let binding = ThrowingAsyncBinding<String, Never>("hello")
        guard case .success(let value) = binding.loadingState else {
            Issue.record("Expected .success, got \(binding.loadingState)")
            return
        }
        #expect(value == "hello")
    }
    
    
    // MARK: Generator init - success path
    
    @Test("Generator init: wrappedValue returns the generated value")
    func generatorInitWrappedValue() async throws {
        let binding = ThrowingAsyncBinding<Int, Never> { 7 }
        let value = try await binding.wrappedValue
        #expect(value == 7)
    }
    
    
    @Test("Generator init: reading loadingState triggers loading and eventually resolves")
    func generatorInitLoadingStateTriggersLoad() async throws {
        let binding = ThrowingAsyncBinding<Int, Never> { 55 }
        
        // Merely touching loadingState should kick off the load. We don't care
        // what state we observe *here* — the contract is just that after we
        // await wrappedValue, the binding has resolved.
        _ = binding.loadingState
        _ = try await binding.wrappedValue
        
        guard case .success(let value) = binding.loadingState else {
            Issue.record("Expected .success after loading completed, got \(binding.loadingState)")
            return
        }
        #expect(value == 55)
    }
    
    
    @Test("Generator init: generator is called at most once across multiple reads")
    func generatorCalledOnce() async throws {
        let callCount = Mutex(0)
        let binding = ThrowingAsyncBinding<Int, Never> {
            await callCount.run { $0 += 1 }
            return 42
        }
        
        _ = try await binding.wrappedValue
        _ = try await binding.wrappedValue
        _ = try await binding.wrappedValue
        
        let count = await callCount.run { $0 }
        #expect(count == 1, "Generator should be called once; result must be cached")
    }
    
    
    // MARK: Generator init - failure path
    
    @Test("Throwing generator: wrappedValue re-throws the error")
    func throwingGeneratorRethrows() async {
        struct LoadError: Error, Equatable {}
        
        let binding = ThrowingAsyncBinding<Int, LoadError> { () throws(LoadError) in
            throw LoadError()
        }
        
        do {
            _ = try await binding.wrappedValue
            Issue.record("Expected LoadError to be thrown")
        }
        catch {
            // Typed throws guarantees only LoadError can be thrown; reaching here is the assertion.
        }
    }
    
    
    @Test("Throwing generator: loadingState transitions to .failure")
    func throwingGeneratorLoadingState() async {
        struct LoadError: Error {}
        
        let binding = ThrowingAsyncBinding<Int, LoadError> { () throws(LoadError) in
            throw LoadError()
        }
        
        _ = try? await binding.wrappedValue
        
        guard case .failure = binding.loadingState else {
            Issue.record("Expected .failure, got \(binding.loadingState)")
            return
        }
    }
    
    
    @Test("Throwing generator: failure is cached; generator runs once even across repeated failed reads")
    func failureIsCached() async {
        struct LoadError: Error, Equatable {}
        
        let callCount = Mutex(0)
        let binding = ThrowingAsyncBinding<Int, LoadError> { () throws(LoadError) in
            await callCount.run { $0 += 1 }
            throw LoadError()
        }
        
        for _ in 1...3 {
            do {
                _ = try await binding.wrappedValue
                Issue.record("Expected LoadError on each read")
            }
            catch {
                // Typed throws guarantees only LoadError can be thrown.
            }
        }
        
        let count = await callCount.run { $0 }
        #expect(count == 1, "Generator must run once even after multiple failed reads")
    }
    
    
    // MARK: setWrappedValue
    
    @Test("setWrappedValue: updates wrappedValue")
    func setWrappedValueUpdates() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(0)
        await binding.setWrappedValue(99)
        let value = try await binding.wrappedValue
        #expect(value == 99)
    }
    
    
    @Test("setWrappedValue: bypasses the generator when called before any read")
    func setWrappedValueBypassesGenerator() async throws {
        let callCount = Mutex(0)
        let binding = ThrowingAsyncBinding<Int, Never> {
            await callCount.run { $0 += 1 }
            return -1  // would be wrong if the generator ran
        }
        
        // Set first, then read — the generator should never be touched.
        await binding.setWrappedValue(42)
        let value = try await binding.wrappedValue
        
        #expect(value == 42)
        let count = await callCount.run { $0 }
        #expect(count == 0, "Generator must not run when setWrappedValue is called first")
    }
    
    
    @Test("setWrappedValue: replaces a stored failure with success")
    func setWrappedValueRecoversFromFailure() async throws {
        struct LoadError: Error {}
        
        let binding = ThrowingAsyncBinding<Int, LoadError> { () throws(LoadError) in
            throw LoadError()
        }
        
        // Drive into failure.
        _ = try? await binding.wrappedValue
        
        // Recovery: overwrite with success.
        await binding.setWrappedValue(7)
        let value = try await binding.wrappedValue
        #expect(value == 7)
        
        guard case .success = binding.loadingState else {
            Issue.record("Expected .success after recovery, got \(binding.loadingState)")
            return
        }
    }
    
    
    // MARK: mutateWrappedValue(throwingSetter:)
    
    @Test("mutateWrappedValue: setter receives the current success")
    func mutateReceivesCurrentSuccess() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(10)
        
        let observed = Mutex<Int?>(nil)
        await binding.mutateWrappedValue(throwingSetter: { result in
            if case .success(let v) = result {
                await observed.run { $0 = v }
            }
        })
        
        let seen = await observed.run { $0 }
        #expect(seen == 10, "Setter should have seen the current value (10)")
    }
    
    
    @Test("mutateWrappedValue: preserves the mutation")
    func mutatePreservesMutation() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(10)
        
        await binding.mutateWrappedValue(throwingSetter: { result in
            if case .success(let v) = result {
                result = .success(v * 2)
            }
        })
        
        let value = try await binding.wrappedValue
        #expect(value == 20)
    }
    
    
    @Test("mutateWrappedValue: when the setter throws, binding transitions to .failure")
    func mutateThrowSetsBindingToFailure() async throws {
        struct MutationError: Error, Equatable {}
        
        let binding = ThrowingAsyncBinding<Int, MutationError>(0)
        
        await binding.mutateWrappedValue(throwingSetter: { _ throws(MutationError) in
            throw MutationError()
        })
        
        guard case .failure = binding.loadingState else {
            Issue.record("Expected .failure after setter threw, got \(binding.loadingState)")
            return
        }
    }
    
    
    @Test("mutateWrappedValue: setter sees current failure when binding is in failure state")
    func mutateOnFailedBindingReceivesFailure() async {
        struct LoadError: Error, Equatable {}
        
        let binding = ThrowingAsyncBinding<Int, LoadError> { () throws(LoadError) in
            throw LoadError()
        }
        
        // Drive into failure.
        _ = try? await binding.wrappedValue
        
        let sawFailure = Mutex(false)
        await binding.mutateWrappedValue(throwingSetter: { result in
            if case .failure = result {
                await sawFailure.run { $0 = true }
            }
        })
        
        let seen = await sawFailure.run { $0 }
        #expect(seen, "Setter should have seen the current .failure")
    }
    
    
    // MARK: refresh
    
    /// Conservative test: just asserts the value is still available after refresh.
    /// `refresh()` currently doesn't clear the cache, so the generator doesn't actually
    /// re-run on a generator-init binding — see notes in the package.
    @Test("refresh: value remains available afterwards")
    func refreshPreservesValue() async throws {
        let binding = ThrowingAsyncBinding<Int, Never>(42)
        binding.refresh()
        let value = try await binding.wrappedValue
        #expect(value == 42)
    }
    
    
    // MARK: Concurrency
    
    /// Many tasks awaiting `wrappedValue` while loading should ALL receive
    /// the result once it resolves — not just the first one in line.
    @Test("Multiple concurrent waiters on wrappedValue all receive the resolved value",
          .timeLimit(.minutes(1)))
    func multipleWaitersReceiveValue() async throws {
        // A short async pause in the generator gives later waiters time to
        // arrive and park on `subject.values` while loading is still in flight.
        // We don't try to choreograph exact interleavings — the contract is
        // simply that every waiter eventually receives the value, no matter
        // when they showed up.
        let binding = ThrowingAsyncBinding<Int, Never> {
            try? await Task.sleep(for: .milliseconds(50))
            return 42
        }
        
        let collected = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try! await binding.wrappedValue
                }
            }
            var results: [Int] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        #expect(collected.count == 10, "All 10 waiters should receive a result")
        #expect(collected.allSatisfy { $0 == 42 }, "Every waiter should receive the correct value")
    }
    
    
    /// Hammering `loadingState` from many tasks at once must not cause the
    /// generator to run more than once. The cache inside the getter mutex is
    /// what guarantees this.
    @Test("Concurrent loadingState access triggers the generator only once",
          .timeLimit(.minutes(1)))
    func concurrentLoadingStateAccessOnlyOneLoad() async throws {
        // Repeat to surface any rare race conditions.
        for _ in 1...20 {
            let callCount = Mutex(0)
            let binding = ThrowingAsyncBinding<Int, Never> {
                await callCount.run { $0 += 1 }
                return 1
            }
            
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<10 {
                    group.addTask {
                        _ = binding.loadingState
                    }
                }
            }
            
            // Wait for loading to finish.
            _ = try await binding.wrappedValue
            
            let count = await callCount.run { $0 }
            #expect(count == 1, "Generator must run exactly once regardless of concurrent loadingState access")
        }
    }
    
    
    // MARK: set: callback contract
    //
    // These tests describe how the `set:` callback is expected to behave.
    // They follow the SwiftUI `Binding(get:set:)` model: the callback fires
    // when the binding is changed by a caller (via `setWrappedValue` or
    // `mutateWrappedValue`), not when the generator loads the initial value
    // or refreshes it. The new state is delivered to the callback before
    // the mutating call returns.
    
    @Test("setWrappedValue invokes the set callback with the new value")
    func setCallbackFiresOnSetWrappedValue() async {
        typealias State = FailableLoadingState<Int, Never>
        let received = Mutex<State?>(nil)
        
        let binding = ThrowingAsyncBinding<Int, Never>(
            0,
            set: { state in
                await received.run { $0 = state }
            }
        )
        
        await binding.setWrappedValue(42)
        
        let observed = await received.run { $0 }
        guard case .success(42) = observed else {
            Issue.record("Expected set callback to receive .success(42); got \(String(describing: observed))")
            return
        }
    }
    
    
    @Test("mutateWrappedValue invokes the set callback with the post-mutation value")
    func setCallbackFiresAfterSuccessfulMutate() async {
        typealias State = FailableLoadingState<Int, Never>
        let received = Mutex<State?>(nil)
        
        let binding = ThrowingAsyncBinding<Int, Never>(
            10,
            set: { state in
                await received.run { $0 = state }
            }
        )
        
        await binding.mutateWrappedValue(throwingSetter: { result in
            if case .success(let v) = result {
                result = .success(v * 2)
            }
        })
        
        let observed = await received.run { $0 }
        guard case .success(20) = observed else {
            Issue.record("Expected set callback to receive .success(20); got \(String(describing: observed))")
            return
        }
    }
    
    
    @Test("mutateWrappedValue invokes the set callback with .failure when the setter throws")
    func setCallbackFiresOnThrowingMutate() async {
        struct MutationError: Error, Equatable {}
        typealias State = FailableLoadingState<Int, MutationError>
        let received = Mutex<State?>(nil)
        
        let binding = ThrowingAsyncBinding<Int, MutationError>(
            0,
            set: { state in
                await received.run { $0 = state }
            }
        )
        
        await binding.mutateWrappedValue(throwingSetter: { _ throws(MutationError) in
            throw MutationError()
        })
        
        let observed = await received.run { $0 }
        guard case .failure = observed else {
            Issue.record("Expected set callback to receive .failure; got \(String(describing: observed))")
            return
        }
    }
}



// MARK: - ThrowingAsyncLazy

@Suite("ThrowingAsyncLazy")
struct ThrowingAsyncLazyTests {
    
    @Test("Static init: wrappedValue returns the initial value")
    func staticInit() async throws {
        let lazy = ThrowingAsyncLazy<String, Never>("swift")
        let value = try await lazy.wrappedValue
        #expect(value == "swift")
    }
    
    
    @Test("Generator init: wrappedValue returns the generated value")
    func generatorInit() async throws {
        let lazy = ThrowingAsyncLazy<Int, Never>(get: { 123 })
        let value = try await lazy.wrappedValue
        #expect(value == 123)
    }
    
    
    @Test("Throwing generator: wrappedValue re-throws the error")
    func throwingGenerator() async {
        struct LazyError: Error, Equatable {}
        
        let lazy = ThrowingAsyncLazy<Int, LazyError>(
            get: { () throws(LazyError) in throw LazyError() }
        )
        
        do {
            _ = try await lazy.wrappedValue
            Issue.record("Expected LazyError")
        }
        catch {
            // Typed throws guarantees only LazyError can be thrown.
        }
    }
    
    
    @Test("Generator init: generator is called at most once across multiple reads")
    func generatorCalledOnce() async throws {
        let callCount = Mutex(0)
        let lazy = ThrowingAsyncLazy<Int, Never>(get: {
            await callCount.run { $0 += 1 }
            return 5
        })
        
        _ = try await lazy.wrappedValue
        _ = try await lazy.wrappedValue
        
        let count = await callCount.run { $0 }
        #expect(count == 1, "Generator should only be called once")
    }
}



// MARK: - AsyncBinding

@Suite("AsyncBinding")
struct AsyncBindingTests {
    
    // MARK: Static value init
    
    @Test("Static init: wrappedValue returns the initial value")
    func staticInitWrappedValue() async {
        let binding = AsyncBinding(42)
        let value = await binding.wrappedValue
        #expect(value == 42)
    }
    
    
    @Test("Static init: loadingState is .success immediately")
    func staticInitLoadingState() {
        let binding = AsyncBinding(99)
        guard case .success(let value) = binding.loadingState else {
            Issue.record("Expected .success, got \(binding.loadingState)")
            return
        }
        #expect(value == 99)
    }
    
    
    // MARK: Generator init
    
    @Test("Generator init: wrappedValue returns the generated value")
    func generatorInitWrappedValue() async {
        let binding = AsyncBinding<String> { "generated" }
        let value = await binding.wrappedValue
        #expect(value == "generated")
    }
    
    
    @Test("Generator init: generator is called at most once across multiple reads")
    func generatorCalledOnce() async {
        let callCount = Mutex(0)
        let binding = AsyncBinding<Int> {
            await callCount.run { $0 += 1 }
            return 7
        }
        
        _ = await binding.wrappedValue
        _ = await binding.wrappedValue
        _ = await binding.wrappedValue
        
        let count = await callCount.run { $0 }
        #expect(count == 1, "Generator should only be called once; result must be cached")
    }
    
    
    // MARK: setWrappedValue
    
    @Test("setWrappedValue: updates wrappedValue")
    func setWrappedValueUpdates() async {
        let binding = AsyncBinding(0)
        await binding.setWrappedValue(77)
        let value = await binding.wrappedValue
        #expect(value == 77)
    }
    
    
    // MARK: mutateWrappedValue
    
    /// This is the regression test for the silent-mutation-loss bug:
    /// the inner closure used to extract the value via `case .success(var value)`
    /// and mutate it, but never write it back into `result`. The fix is to
    /// reassign `result = .success(value)` after the setter runs.
    @Test("mutateWrappedValue: preserves the mutation (regression: was silently dropped)")
    func mutatePreservesMutation() async {
        let binding = AsyncBinding(10)
        
        await binding.mutateWrappedValue(setter: { value in
            value *= 2
        })
        
        let value = await binding.wrappedValue
        #expect(value == 20, "Mutation must be preserved; if this returns 10, the silent-drop bug is back")
    }
    
    
    @Test("mutateWrappedValue: multiple sequential mutations each preserve their changes")
    func mutateMultipleSequential() async {
        let binding = AsyncBinding(0)
        
        for _ in 0..<5 {
            await binding.mutateWrappedValue(setter: { $0 += 1 })
        }
        
        let value = await binding.wrappedValue
        #expect(value == 5, "All five sequential increments must be preserved")
    }
    
    
    // MARK: refresh
    
    @Test("refresh: value remains available afterwards")
    func refreshPreservesValue() async {
        let binding = AsyncBinding(42)
        binding.refresh()
        let value = await binding.wrappedValue
        #expect(value == 42)
    }
    
    
    // MARK: Concurrency
    
    @Test("Multiple concurrent waiters on wrappedValue all receive the resolved value",
          .timeLimit(.minutes(1)))
    func multipleWaitersReceiveValue() async {
        // See the matching test in `ThrowingAsyncBindingTests` for the reasoning
        // behind the sleep-based design.
        let binding = AsyncBinding<Int> {
            try? await Task.sleep(for: .milliseconds(50))
            return 42
        }
        
        let collected = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await binding.wrappedValue
                }
            }
            var results: [Int] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        #expect(collected.count == 10)
        #expect(collected.allSatisfy { $0 == 42 })
    }
    
    
    // MARK: set: callback contract
    
    // Same contract as `ThrowingAsyncBindingTests`: the callback fires when
    // the binding is changed by a caller, with the new state, before the
    // mutating call returns. For `AsyncBinding` the state is always `.success`
    // (since the non-throwing variants can't transition to `.failure`).
    
    @Test("setWrappedValue invokes the set callback with the new value") // Succeeds if debugged. Race condition?
    func setCallbackFiresOnSetWrappedValue() async {
        typealias State = AsyncBinding<Int>.LoadingState
        let received = Mutex<State?>(nil)
        
        let binding = AsyncBinding(
            0,
            set: { state in
                await received.run { $0 = state }
            }
        )
        
        await binding.setWrappedValue(42)
        
        let observed = await received.run { $0 }
        guard case .success(42) = observed else {
            Issue.record("Expected set callback to receive .success(42); got \(String(describing: observed))")
            return
        }
    }
    
    
    @Test("mutateWrappedValue invokes the set callback with the post-mutation value")
    func setCallbackFiresAfterMutate() async {
        typealias State = FailableLoadingState<Int, Never>
        let received = Mutex<State?>(nil)
        
        let binding = AsyncBinding(
            10,
            set: { state in
                await received.run { $0 = state }
            }
        )
        
        await binding.mutateWrappedValue(setter: { value in
            value *= 2
        })
        
        let observed = await received.run { $0 }
        guard case .success(20) = observed else {
            Issue.record("Expected set callback to receive .success(20); got \(String(describing: observed))")
            return
        }
    }
}



// MARK: - AsyncLazy

@Suite("AsyncLazy")
struct AsyncLazyTests {
    
    @Test("Static init: wrappedValue returns the initial value")
    func staticInit() async {
        let lazy = AsyncLazy("stored")
        let value = await lazy.wrappedValue
        #expect(value == "stored")
    }
    
    
    @Test("Static init: loadingState is .success immediately")
    func staticLoadingState() {
        let lazy = AsyncLazy(true)
        guard case .success(let value) = lazy.loadingState else {
            Issue.record("Expected .success, got \(lazy.loadingState)")
            return
        }
        #expect(value == true)
    }
    
    
    @Test("Generator init: wrappedValue returns the generated value")
    func generatorInit() async {
        let lazy = AsyncLazy<Double> { 3.14 }
        let value = await lazy.wrappedValue
        #expect(value == 3.14)
    }
    
    
    @Test("Generator init: generator is called at most once across multiple reads")
    func generatorCalledOnce() async {
        let callCount = Mutex(0)
        let lazy = AsyncLazy<Int> {
            await callCount.run { $0 += 1 }
            return 7
        }
        
        _ = await lazy.wrappedValue
        _ = await lazy.wrappedValue
        
        let count = await callCount.run { $0 }
        #expect(count == 1, "Generator should only be called once")
    }
}
