//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

extension AsyncSequence where Self: Sendable, AsyncIterator: Sendable, Element: Sendable {
  public func share(_ ways: Int) -> [AsyncShareSequence<Self>] {
    let split = AsyncShareSequence<Self>.Split(self, ways: ways)
    return (0..<ways).map { AsyncShareSequence(split, side: $0) }
  }
}

public struct AsyncShareSequence<Base: AsyncSequence>: AsyncSequence
  where Base: Sendable, Base.AsyncIterator: Sendable, Base.Element: Sendable {
   public typealias Element = Base.Element
   
   struct Split: Sendable {
     enum Side: Sendable {
       case idle
       case waiting(UnsafeContinuation<Bool, Never>)
       case placeholder
       case resolved(Result<Base.Element?, Error>)
       case pending(UnsafeContinuation<Result<Base.Element?, Error>, Never>)
       case cancelled
     }
     
     enum Upstream: Sendable {
       case idle(Base)
       case active(Base.AsyncIterator)
     }
     
     struct State: Sendable {
       var sides: [Side]
       var upstream: Upstream
       
       init(_ base: Base, ways: Int) {
         sides = Array(repeating: .idle, count: ways)
         upstream = .idle(base)
       }
       
       mutating func enter(_ side: Int) -> [UnsafeContinuation<Bool, Never>] {
         var indices = [Int]()
         var collected = [UnsafeContinuation<Bool, Never>]()
         for index in sides.indices {
           switch sides[index] {
           case .waiting(let continuation):
             indices.append(index)
             if side != index {
               collected.append(continuation)
             }
           case .cancelled:
             break
           default:
             collected.removeAll()
             return [] // not fully ready yet
           }
         }
         for index in indices {
           sides[index] = .placeholder
         }
         return collected
       }
       
       mutating func makeAsyncIterator() -> Base.AsyncIterator {
         switch upstream {
         case .idle(let base):
           return base.makeAsyncIterator()
         case .active(let iterator):
           return iterator
         }
       }
       
       mutating func setIterator(_ iterator: Base.AsyncIterator) {
         upstream = .active(iterator)
       }
     }
     
     let state: ManagedCriticalState<State>
     
     init(_ base: Base, ways: Int) {
       state = ManagedCriticalState(State(base, ways: ways))
     }
     
     func cancel(_ side: Int) {
       var waiting: UnsafeContinuation<Bool, Never>?
       var pending: UnsafeContinuation<Result<Base.Element?, Error>, Never>?
       let continuations = state.withCriticalRegion { state -> [UnsafeContinuation<Bool, Never>] in
         switch state.sides[side] {
         case .waiting(let continuation):
           waiting = continuation
         case .pending(let continuation):
           pending = continuation
         default: break
         }
         state.sides[side] = .cancelled
         return state.enter(side)
       }
       waiting?.resume(returning: false)
       var continuationIterator = continuations.makeIterator()
       if let first = continuationIterator.next() {
         while let continuation = continuationIterator.next() {
           continuation.resume(returning: false)
         }
         first.resume(returning: true)
       }
       pending?.resume(returning: .success(nil))
     }
     
     func next(_ side: Int) async -> Result<Base.Element?, Error> {
       let resumer = await withUnsafeContinuation { (continuation: UnsafeContinuation<Bool, Never>) in
         let continuations = state.withCriticalRegion { state -> [UnsafeContinuation<Bool, Never>] in
           state.sides[side] = .waiting(continuation)
           return state.enter(side)
         }
         
         for continuation in continuations {
           continuation.resume(returning: false)
         }
         if continuations.count > 0 {
           continuation.resume(returning: true)
         }
       }
       if resumer {
         let task: Task<Result<Base.Element?, Error>, Never> = Task {
           var iterator = state.withCriticalRegion { $0.makeAsyncIterator() }
           let result: Result<Base.Element?, Error>
           do {
             let value = try await iterator.next()
             result = .success(value)
           } catch {
             result = .failure(error)
           }
           
           var continuations = [UnsafeContinuation<Result<Base.Element?, Error>, Never>]()
           state.withCriticalRegion { state in
             for index in state.sides.indices {
               switch state.sides[index] {
               case .placeholder:
                 state.sides[index] = .resolved(result)
               case .pending(let continuation):
                 state.sides[index] = .idle
                 continuations.append(continuation)
               default:
                 break
               }
             }
             state.setIterator(iterator)
           }
           for continuation in continuations {
             continuation.resume(returning: result)
           }
           return result
         }
         return await withTaskCancellationHandler {
           let forward = state.withCriticalRegion { state -> Bool in
             for index in state.sides.indices {
               if index != side {
                 switch state.sides[index] {
                 case .cancelled:
                   continue
                 default:
                   return false
                 }
               }
             }
             return true
           }
           if forward {
             task.cancel()
           }
         } operation: {
           return await task.value
         }
       } else {
         return await withUnsafeContinuation { continuation in
           let result = state.withCriticalRegion { state -> Result<Base.Element?, Error>? in
             switch state.sides[side] {
             case .resolved(let result):
               state.sides[side] = .idle
               return result
             default:
               state.sides[side] = .pending(continuation)
               return nil
             }
           }
           if let result = result {
             continuation.resume(returning: result)
           }
         }
       }
     }
   }

   public struct Iterator: AsyncIteratorProtocol {
     final class Side: Sendable {
       let split: Split
       let side: Int
       
       init(_ split: Split, side: Int) {
         self.split = split
         self.side = side
       }
       
       deinit {
         split.cancel(side)
       }

       func next() async rethrows -> Base.Element? {
         return try await split.next(side)._rethrowGet()
       }
     }
     
     let side: Side
     
     init(_ split: Split, side: Int) {
       self.side = Side(split, side: side)
     }
     
     public mutating func next() async rethrows -> Base.Element? {
       return try await side.next()
     }
   }
   
   let split: Split
   let side: Int
   
   init(_ split: Split, side: Int) {
     self.split = split
     self.side = side
   }

   public func makeAsyncIterator() -> Iterator {
     Iterator(split, side: side)
   }
 }

 extension AsyncShareSequence: Sendable where Base.Element: Sendable { }
 extension AsyncShareSequence.Iterator: Sendable where Base.Element: Sendable { }

