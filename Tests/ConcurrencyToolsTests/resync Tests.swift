//
//  resync Tests.swift
//  ConcurrencyTools
//
//  Created by Ky on 2023-05-22.
//  Migrated to Swift Testing on 2026-05-14.
//

import Testing
import ConcurrencyTools



@Suite("resync")
struct ResyncTests {
    
    /// Confirms that `resync` can drive a throwing async function to completion
    /// from a synchronous context.
    ///
    /// In Swift Testing, an unexpected thrown error fails the test on its own,
    /// so we just call `try resync(...)` without an explicit assertion.
    @Test("Drives a throwing async function to completion",
          .timeLimit(.minutes(1)))
    func resyncThrowing() throws {
        _ = try resync(TestActor.default.int)
    }
    
    
    /// Confirms that `resync` also drives the non-throwing overload to completion.
    @Test("Drives a non-throwing async function to completion",
          .timeLimit(.minutes(1)))
    func resyncNonThrowing() {
        _ = resync(TestActor.default.int_nothrow)
    }
}
