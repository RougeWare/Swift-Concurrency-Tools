//
//  GlobalActor sugar.swift
//  ConcurrencyTools
//
//  Created by Ky on 2024-12-27.
//

import Foundation



//public extension GlobalActor where ActorType == Self {
//    
//    func run<Value, Failure: Error>(_ isolatedBlock: () async throws(Failure) -> Value) async rethrows -> Value {
//        try await isolatedBlock()
//    }
//    
//    
//    
//    func run<Value>(_ isolatedBlock: () async -> Value) async -> Value {
//        await isolatedBlock()
//    }
//    
//    
//    
//    static func run<Value, Failure: Error>(_ isolatedBlock: () async throws(Failure) -> Value) async rethrows -> Value {
//        try await Self.shared.run(isolatedBlock)
//    }
//    
//    
//    static func run<Value>(_ isolatedBlock: () async -> Value) async -> Value {
//        await Self.shared.run(isolatedBlock)
//    }
//}
//
//
//
//
//@globalActor
//actor TestActor: GlobalActor {
//    static let shared = TestActor()
//    
//    var value = ""
//}
//
//
//func test() async {
//    let a = TestActor()
//    
//    await TestActor.run {
//        locked()
//    }
//}
//
//
//
//@TestActor
//func locked() {
//    print("unlock")
//}
